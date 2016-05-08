nr=$1
e=$2
eo=$3
ns=$4
client=$5
ddir=$6
dop=$7
dlmin=$8
dlmax=$9
dokill=${10}
dname=${11}
only1t=${12}
unique=${13}
rpc=${14}
ips=${15}
nqt=${16}
setup=${17}
mongo=${18}

sfx=dop${dop}.ns${ns}
rm -f o.res.$sfx

maxr=$(( $nr / $dop ))

if [[ $mongo != "yes" ]]; then
$client -uroot -ppw -A -h127.0.0.1 -e 'reset master'
if [[ $setup == "yes" ]] ; then
  $client -uroot -ppw -A -h127.0.0.1 -e 'drop database ib'
  sleep 5
  $client -uroot -ppw -A -h127.0.0.1 -e 'create database ib'
fi
fi

killall vmstat
killall iostat

# python mstat.py --db_user=root --db_password=pw --db_host=127.0.0.1 --loops=10000000 --interval=15 2> /dev/null > o.mstat.$sfx &
# mpid=$!

vmstat 10 >& o.vm.$sfx &
vpid=$!
iostat -kx 10 >& o.io.$sfx &
ipid=$!

fio-status -a >& o.fio.pre.$sfx

start_secs=$( date +%s )

for n in $( seq 1 $dop ) ; do

  if [[ $setup == "yes" ]]; then
    setstr="--setup"
  else
    setstr=""
  fi

  if [[ $only1t == "yes" && $n -gt 1 ]]; then
    setstr=""
  fi  

  if [[ $only1t == "yes" ]]; then
    tn="pi1"
  else
    tn="pi${n}"
  fi

  if [[ $mongo == "yes" ]]; then
    db_args="--mongo --mongo_w=1"
  else
    db_args="--db_user=root --db_password=pw --engine=$e --engine_options=$eo --unique_checks=${unique}"
  fi

  if [[ $ips = 0 ]] ; then
    rpr=100000
  else
    rpr=$(( ips * 10 ))
  fi

  echo iibench.py --db_name=ib --rows_per_report=$rpr --db_host=127.0.0.1 ${db_args} --max_rows=${maxr} --table_name=${tn} $setstr --num_secondary_indexes=$ns --data_length_min=$dlmin --data_length_max=$dlmax --rows_per_commit=${rpc} --inserts_per_second=${ips} --query_threads=${nqt} > o.ib.dop${dop}.ns${ns}.${n} 
  python iibench.py --db_name=ib --rows_per_report=$rpr --db_host=127.0.0.1 ${db_args} --max_rows=${maxr} --table_name=${tn} $setstr --num_secondary_indexes=$ns --data_length_min=$dlmin --data_length_max=$dlmax --rows_per_commit=${rpc} --inserts_per_second=${ips} --query_threads=${nqt} >> o.ib.dop${dop}.ns${ns}.${n} 2>&1 &

  pids[${n}]=$!
  
  if [[ $only1t == "yes" ]]; then
    sleep 5
  fi
 
done

for n in $( seq 1 $dop ) ; do
  # echo Wait for ${pids[${n}]} $n
  wait ${pids[${n}]} 
done

stop_secs=$( date +%s )
tot_secs=$(( $stop_secs - $start_secs ))
insert_rate=$( echo "scale=1; $nr / $tot_secs" | bc )
insert_per=$( echo "scale=1; $insert_rate / $dop" | bc )

total_query=$( for n in $( seq 1 $dop ); do tail -2 o.ib.dop${dop}.ns${ns}.$n | head -1 ; done | awk '{ tq += $7; } END { print tq }' )
query_rate=$( echo "scale=1; $total_query / $tot_secs" | bc )

# echo $dop processes, $maxr rows-per-process, $tot_secs seconds, $insert_rate rows-per-second, $insert_per rows-per-second-per-user
echo $dop processes, $maxr rows-per-process, $tot_secs seconds, $insert_rate rows-per-second, $insert_per rows-per-second-per-user, $total_query queries, $query_rate queries-per-second > o.res.$sfx

# kill $mpid >& /dev/null
kill $vpid >& /dev/null
kill $ipid >& /dev/null
fio-status -a >& o.fio.post.$sfx

if [[ $mongo == "no" ]]; then
$client -uroot -ppw -A -h127.0.0.1 -e 'show engine innodb status\G' > o.esi.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'show engine rocksdb status\G' > o.esr.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'show engine tokudb status\G' > o.est.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'show global status' > o.gs.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'show global variables' > o.gv.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'show memory status\G' > o.mem.$sfx
$client -uroot -ppw -A -h127.0.0.1 ib -e 'show table status' > o.ts.$sfx
$client -uroot -ppw -A -h127.0.0.1 -e 'reset master'
else
echo "db.serverStatus()" | $client > o.es.$sfx
echo "db.pi1.stats()" | $client ib > o.tab.$sfx
fi

du -hs $ddir > o.sz.$sfx
echo "with apparent size " >> o.sz.$sfx
du -hs --apparent-size $ddir >> o.sz.$sfx
echo "all" >> o.sz.$sfx
du -hs ${ddir}/* > o.sz.$sfx

printf "\niostat, vmstat normalized by insert rate\n" >> o.res.$sfx
printf "samp\tr/s\trkb/s\twkb/s\tr/q\trkb/q\twkb/q\tips\n" >> o.res.$sfx
grep $dname o.io.$sfx | awk '{ rs += $4; rkb += $6; wkb += $7; c += 1 } END { printf "%s\t%.1f\t%.0f\t%.0f\t%.3f\t%.6f\t%.6f\t%s\n", c, rs/c, rkb/c, wkb/c, rs/c/q, rkb/c/q, wkb/c/q, q }' q=${insert_rate} >> o.res.$sfx

printf "\nsamp\tcs/s\tcpu/c\tcs/q\tcpu/q\n" >> o.res.$sfx
grep -v swpd o.vm.$sfx | awk '{ cs += $12; cpu += $13 + $14; c += 1 } END { printf "%s\t%.0f\t%.1f\t%.3f\t%.6f\n", c, cs/c, cpu/c, cs/c/q, cpu/c/q }' q=${insert_rate} >> o.res.$sfx

printf "\niostat, vmstat normalized by query rate\n" >> o.res.$sfx
printf "samp\tr/s\trkb/s\twkb/s\tr/q\trkb/q\twkb/q\tips\n" >> o.res.$sfx
grep $dname o.io.$sfx | awk '{ rs += $4; rkb += $6; wkb += $7; c += 1 } END { printf "%s\t%.1f\t%.0f\t%.0f\t%.3f\t%.6f\t%.6f\t%s\n", c, rs/c, rkb/c, wkb/c, rs/c/q, rkb/c/q, wkb/c/q, q }' q=${query_rate} >> o.res.$sfx

printf "\nsamp\tcs/s\tcpu/c\tcs/q\tcpu/q\n" >> o.res.$sfx
grep -v swpd o.vm.$sfx | awk '{ cs += $12; cpu += $13 + $14; c += 1 } END { printf "%s\t%.0f\t%.1f\t%.3f\t%.6f\n", c, cs/c, cpu/c, cs/c/q, cpu/c/q }' q=${query_rate} >> o.res.$sfx

echo >> o.res.$sfx
du -hs $ddir >> o.res.$sfx

echo >> o.res.$sfx
ps auxww | grep mysqld | grep -v mysqld_safe | grep -v grep >> o.res.$sfx
ps auxww | grep mongod | grep -v grep >> o.res.$sfx

printf "\ninsert and query rate at nth percentile\n" >> o.res.$sfx
for n in $( seq 1 $dop ) ; do
  lines=$( awk '{ if (NF == 9) { print $6 } }' o.ib.dop${dop}.ns${ns}.${n} | wc -l )
  for x in 50 75 90 95 99 ; do
    off=$( printf "%.0f" $( echo "scale=3; ($x / 100.0 ) * $lines " | bc ) )
    i_nth=$( awk '{ if (NF == 9) { print $6 } }' o.ib.dop${dop}.ns${ns}.${n} | sort -rnk 1,1 | head -${off} | tail -1 )
    q_nth=$( awk '{ if (NF == 9) { print $9 } }' o.ib.dop${dop}.ns${ns}.${n} | sort -rnk 1,1 | head -${off} | tail -1 )
    echo ${x}th, ${off} / ${lines} = $i_nth insert, $q_nth query >> o.res.$sfx
  done
done

cat o.res.$sfx
