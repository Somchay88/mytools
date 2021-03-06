max_concur=$1

# 1 means use binlog & trxlog
use_bltl=$2

# 1 means use doublewrite buffer
use_dblw=$3

# multiplier for max_concur, 2, 4, 8 etc
concur_mult=$4

# name of storage device in iostat output
dev=$5

for d in 0 6 17 25 100 ; do rm -f dr.$d dw.$d p.$d percentile_iops.$d report.$d io.$d ; done
rm -f r 

u=1
while [ $u -le $max_concur ]; do
for d in 0 6 17 25 100 ; do

suffix=o.bl_${use_bltl}.trx_${use_bltl}.dblwr_${use_dblw}.wthr_8.uthr_${u}.dirty_$d

grep final ${suffix}* | grep read: | awk '{ printf   "%.0f\t%s\t%s\t%s\t%s\t%s\t%.1f\t\n", $5, $7, $9, $11, $13, $15, $17 }' >> dr.$d 
grep final ${suffix}* | grep ^write: | awk '{ printf "%.0f\t%s\t%s\t%s\t%s\t%s\t%.1f\t\n", $5, $7, $9, $11, $13, $15, $17 }' >> dw.$d 

iosuffix=i.bl_${use_bltl}.trx_${use_bltl}.dblwr_${use_dblw}.wthr_8.uthr_${u}.dirty_$d
grep $dev ${iosuffix}* |  awk '{ c += 1; rs += $4; ws += $5 ; rkb += $6; wkb += $7 } END { printf "%.0f\t%.0f\t%.0f\t%.0f\n", rs/c, rkb/c, ws/c, wkb/c }' >> io.$d

done
u=$(( $u * $concur_mult ))
done

u=1
while [ $u -le $max_concur ]; do
suffix=o.bl_${use_bltl}.trx_${use_bltl}.dblwr_${use_dblw}.wthr_8.uthr_${u}.dirty_0
grep final ${suffix}* | grep read:
u=$(( $u * $concur_mult ))
done | awk '{ printf "%.0f\n", $5 }' > r

for d in 0 6 17 25 100 ; do paste dr.$d dw.$d r io.$d > p.$d ; done

for d in 0 6 17 25 100 ; do

echo "r_IO - average read IOPs" > report.$d
echo "r_avlat - average read IO latency in millisecs" >> report.$d
echo "r_9X - 9Xth percentile read latency in millisecs" >> report.$d
echo "r_mxlat - max read IO latency in millisecs" >> report.$d
echo "w_IO - average write IOPs" >> report.$d
echo "w_avlat - average write IO latency in millisecs" >> report.$d
echo "w_9X - 9Xth percentile write latency in millisecs" >> report.$d
echo "w_mxlat - max write IO latency in millisecs" >> report.$d
echo "ro_mx - average read IOPs for read-only test with same concurrency" >> report.$d
echo "io.r, io.rkb, io.w, io.wkb - average rates from iostat for r/s, rkb/s, w/s, wkb/s" >> report.$d
echo "" >> report.$d
echo r_IO r_avlat r_95 r_99 r_99.9 r_99.99 r_mxlat w_IO w_avlat w_95 w_99 w_99.9 w_99.99 w_mxlat ro_mx io_r io_rkb io_w io_wkb | \
  awk '{ printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19 }' >> report.$d

awk '{ printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19 }' p.$d >> report.$d

done

for d in 0 6 17 25 100 ; do

echo "read IOPs at different percentiles over per-interval output" > percentile_iops.$d
echo p50 p75 p90 p95 p96 p97 p98 p99 | \
    awk '{ printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $1, $2, $3, $4, $5, $6, $7, $8 }' >> \
    percentile_iops.$d

u=1
while [ $u -le $max_concur ]; do

suffix=o.bl_${use_bltl}.trx_${use_bltl}.dblwr_${use_dblw}.wthr_8.uthr_${u}.dirty_$d
grep "^final percentile rd IOPs" ${suffix}* | \
    awk '{ printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", $5, $7, $9, $11, $13, $15, $17, $19 }'

u=$(( $u * $concur_mult ))
done >> percentile_iops.$d
done

