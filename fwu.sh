#!/bin/sh

# luna firmware upgrade  script
# $1 image destination (0 or 1) 
# Kernel and root file system images are assumed to be located at the same directory named uImage and rootfs respectively
# ToDo: use arugements to refer to kernel/rootfs location.

k_img="uImage"
r_img="rootfs"
img_ver="fwu_ver"
md5_cmp="md5.txt"
md5_cmd="/bin/md5sum"
#md5 run-time result
md5_tmp="md5_tmp" 
md5_rt_result="md5_rt_result.txt"
# Added "fwu_len" by peicho for bug#0003445
fwu_size_file="fwu_len"
web_logo_oui1="=14a72b"
web_logo_oui2="=8cc7c3"
weblock_ver2="/tmp/web_lockver"
CheckVer="/etc/version"
# Added by Samson
# check if v2801hw

echo `flash get ELAN_MAC_ADDR` > $weblock_ver2
if cat $weblock_ver2 | grep $web_logo_oui1; then
	echo "oui"$web_logo_oui1
elif cat $weblock_ver2 | grep $web_logo_oui2; then
	echo "oui"$web_logo_oui2
else
	echo "cusMac check failed."
	exit 1
fi
echo "cusMac check pass."

if 
# Modified by Jack.Tam on 2017-05-04. For BUG#0002812.
#        cat /proc/mtd | grep linux
        cat /proc/mtd | grep \"k1\"
then    
#        kname="linux"
#        rname="rootfs"
#        kname="k"$1""
#        rname="r"$1""
        kname=\"k"$1"\"
        rname=\"r"$1"\"
elif      
#it's v2801rw check if 16M flash
#        cat /proc/mtd | grep k"$1"
        cat /proc/mtd | grep linux
then            
#        kname="k"$1""
#        rname="r"$1""
        kname="linux"
        rname="rootfs"
# Added by Jack.Tam on 2017-06-06. For BUG#0002847.
        nv setenv sw_commit "0"
# End of BUG#0002847.
# End of BUG#0002812.
else
#it's 8M flash
        kname="k0"
        rname="r0"
#set commit image back to 0, 20161018
	nv setenv sw_commit "0"
fi
echo "==>$kname  ==>$rname"

# Stop this script upon any error
set -e

# Added by peicho for Check software version
if cat $CheckVer | grep '^V2.0.[0-9]*-[0-9][0-9]*'; then
	echo "SOFTVER CHECK FAILD"
	reboot -f
	exit 1
else
	echo "SOFTVER CHECK PASS"
fi
# End of Check software version

# Added by peicho for bug#0003445 to compare the upgeade file size
tar tvf $2 | awk '{print $3, $6}' > $fwu_size_file
nk_mtd=`cat $fwu_size_file | grep "$k_img" | sed '#*//'`
n_k=`echo $nk_mtd | grep "$k_img" | sed 's/uImage.*$//g'`

nr_mtd=`cat $fwu_size_file | grep "$r_img" | sed '#*//'`
n_r=`echo $nr_mtd | grep "$r_img" | sed 's/rootfs.*$//g'`

ok_mtd=`cat /proc/mtd | grep "$kname" | sed '#*//'`
ok_mtd1=`echo ${ok_mtd##*:}`
ok_mtd2=0x`echo ${ok_mtd1:0-1:8}`
o_k=`printf %d $ok_mtd2`

or_mtd=`cat /proc/mtd | grep "$rname" | sed '#*//'`
or_mtd1=`echo ${or_mtd##*:}`
or_mtd2=0x`echo ${or_mtd1:0-1:8}`
o_r=`printf %d $or_mtd2`

echo "new_kernel="$n_k
echo "old_kernel="$o_k
echo "new_system="$n_r
echo "old_system="$o_r

check_k=`busybox expr $n_k - $o_k`
check_r=`busybox expr $n_r - $o_r`

upgeade_flag=0
if [ $check_k -gt 0 ];then 
	echo "kernel size too big!"
	upgeade_flag=1
fi
if [ $check_r -gt 0 ];then 
	echo "filesystem size too big!"
	upgeade_flag=2
fi
if [ $upgeade_flag != 0 ]; then
    echo "invalid upgeade file! upgrade failed!"
    exit 1
else
	echo "valid upgeade file!"
fi
#end of bug#0003445

echo "Updating image $1 with file $2"

# Find out kernel/rootfs mtd partition according to image destination
# Modified by Samson for bug#000269 only one partion for each image 20160318.
#k_mtd="/dev/"`cat /proc/mtd | grep k"$1" | sed 's/:.*$//g'`
#r_mtd="/dev/"`cat /proc/mtd | grep r"$1" | sed 's/:.*$//g'`
k_mtd="/dev/"`cat /proc/mtd | grep "$kname" | sed 's/:.*$//g'`
r_mtd="/dev/"`cat /proc/mtd | grep "$rname" | sed 's/:.*$//g'`

#Ended by Samson.
echo "kernel image is located at $k_mtd"
echo "rootfs image is located at $r_mtd"

#Bohannon add for bug#00003181
flash set CWMP_CT_MWBAND_MODE 0
flash set CWMP_CONFIGURABLE 3
flash set DEVICE_TYPE 1
flash set IPHOST_SRV 0
flash set IPHOST2_SRV 0
# Extract kernel image
tar -xf $2 $k_img -O | md5sum | sed 's/-/'$k_img'/g' > $md5_rt_result
# Check integrity
grep $k_img $md5_cmp > $md5_tmp
diff $md5_rt_result $md5_tmp

if [ $? != 0 ]; then
    echo "$k_img""md5_sum inconsistent, aborted image updating !"
    exit 1
fi

# Extract rootfs image
tar -xf $2 $r_img -O | md5sum | sed 's/-/'$r_img'/g' > $md5_rt_result
# Check integrity
grep $r_img $md5_cmp > $md5_tmp
diff $md5_rt_result $md5_tmp

if [ $? != 0 ]; then
    # rm $r_img
    echo "$r_img""md5_sum inconsistent, aborted image updating !"
    exit 1
fi

echo "Integrity of $k_img & $r_img is okay, start updating"

# Erase kernel partition 
flash_eraseall $k_mtd
# Write kernel partition
echo "Writing $k_img to $k_mtd"
tar -xf $2 $k_img -O > $k_mtd

# Erase rootfs partition 
flash_eraseall $r_mtd
# Write rootfs partition
echo "Writing $r_img to $r_mtd"
tar -xf $2 $r_img -O > $r_mtd

#Added by dyh on 2018-07 for bug#0003304
#Remove by dyh on 2018-08 for OLT Upgrade
#echo 1 > /proc/wdt/enable

# Write image version information 
tar -xf $2 $img_ver 
# Modified by Jack.Tam on 2017-06-06. For BUG#0002847.
#nv setenv sw_version"$1" "`cat $img_ver`"
nv setenv sw_version"$1" "V6.0.1P2T8"
# End of BUG#0002847.

# Clean up temporary files
rm -f $md5_cmp $md5_tmp $md5_rt_result $img_ver $2

# Post processing (for future extension consideration)

echo "Successfully updated image $1!!"

