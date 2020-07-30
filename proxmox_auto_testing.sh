#!/bin/bash
#
# Copyright (c) 2019-2020 Herb Garcia <herbgarcia3001@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.


logdir="/var/log/backy2/"

snapdate=$(date "+%Y_%m_%d")
logname="backy2proxmox_"$snapdate".log"
logspot="$logdir""$logname"
snaplist=$logdir$HOSTNAME"_"$snapdate"_snaps.log"
backy2host="10.10.160.61"
backy2hostfile="/srv/backy2/pending/"$HOSTNAME"_"$snapdate".conf"

logdir="/var/log/backy2/"
diffdir="/srv/backy2/diff/"
date=$(date "+%Y_%m_%d")
logname="proxmox_""$(date "+%Y_%m_%d")"".log"
pool="vmhdd"
logspot=$logdir$logname
snaplist=$logdir$HOSTNAME"_"$date"_snaps.log"
compdir="/srv/backy2/complete/"

for file in /srv/backy2/pending/*.conf; do
    nodelist=`basename "$file"`
    echo "creating diff file and backups of pending snaps in" $nodelist
    echo $(date "+%Y_%m_%d_%H_%M_%S") "creating diff file and backups of pending snaps in" $nodelist >> $logspot
    cat $file | while read -r pendingsnap; do
        pendingdiff=$diffdir$pendingsnap".diff"
        echo "Diff file completed in" $pendingdiff
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Diff file completed in" $pendingdiff > $logspot
        rbd diff --whole-object $pool/$pendingsnap --format=json > $pendingdiff;
        backy2name=${pendingsnap%@*}
        echo "Start backup for" $backy2name
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Start backup for" $backy2name >> $logspot
        SECONDS=0
        backy2 backup -s $pendingsnap -r $pendingdiff rbd://$pool/$pendingsnap $backy2name;
        secs=$SECONDS
        echo "Completed backup for" $backy2name"." "Elapsed time:" $secs "seconds"
        touch $compdir$nodelist
        echo $(date "+%Y_%m_%d_%H_%M_%S") $backy2name "completed." "Elapsed time:" $secs "seconds" > $logspot
        echo $pendingsnap > $compdir$nodelist 
    done < "$nodelist"
    echo "All backups complete for" $nodelist
    echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete for" $nodelist
    
done

echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete." >> $logspot
echo "All backups complete"
