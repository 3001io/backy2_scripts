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

# Assign variables

logdir="/var/log/backy2/"
snapdate=$(date "+%Y_%m_%d")
logname="backy2proxmox_"$snapdate".log"
logspot="$logdir""$logname"
logdir="/var/log/backy2/"
diffdir="/srv/backy2/diff/"
pendir="/srv/backy2/pending/"
compdir="/srv/backy2/complete/"
date=$(date "+%Y_%m_%d")
logname="proxmox_""$(date "+%Y_%m_%d")"".log"
pool="vmhdd"
logspot=$logdir$logname
pendingsnaps=$pendir$date"_pending.snaps"
compsnaps=$compdir$date"_completed.snaps"

# Create sorted lists of snaps that are "completed" (i.e. backed up) and snaps pending backaup.
cat $compdir*.conf > $compsnaps.tmp
sort $compsnaps.tmp > $compsnaps
cat $pendir*.conf > $pendingsnaps.tmp
sort $pendingsnaps.tmp > $pendingsnaps
rm $compsnaps.tmp
rm $pendingsnaps.tmp

# Log progress
echo $(date "+%Y_%m_%d_%H_%M_%S") "creating diff file and backups of pending snaps in" $pendingsnaps >> $logspot
echo "creating diff file and backups of pending snaps in" $pendingsnaps

# Start process for each pending snap in /srv/backy2/pending/pending.snaps
while read -r pendingsnap; do
    echo "creating diff file and backups of pending snap" $pendingsnap

# Trim the snap off to get the volume
    vm=${pendingsnap%@*}

# Trim the volume off to get the snap
    newsnap=${pendingsnap#*@}

# Test to see if the volume was backed up in a previous round of backy2
    if grep -Fq $vm $compsnaps; then

# Create an "oldsnap" to create an RBD diff file in /srv/backy2/diff compared with "newsnap"
        compsnap=$( grep -F $vm $compsnaps )
        oldsnap=${compsnap#*@}
        pendingdiff=$diffdir$pendingsnap".diff"
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Diff file for" $pendingsnap " starting in" $pendingdiff "compared to" $compsnap >> $logspot
        sleep 10
        rbd diff --whole-object $pool/$pendingsnap --from-snap $oldsnap --format=json > $pendingdiff;
        echo "Diff file completed in" $pendingdiff

# Get version UID of the last RBD snapshot
        lastbacky2ver=$( backy2 -m ls $vm | tail -n 1 | cut -d "|" -f 7 )
        echo "Start backup for" $pendingsnap " using diff " $pendingdiff "compared to last backed up snap" $compsnap "at" $lastbacky2ver
        sleep 10

# Use UID to create new backy2 based on the pending snapshot.
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Start backup for" $pendingsnap >> $logspot
        SECONDS=0
        backy2 backup -s $pendingsnap -r $pendingdiff -f $lastbacky2ver rbd://$pool/$compsnap $vm;
#        secs=$SECONDS
        newbacky2ver=$( backy2 -m ls $vm | tail -n  1 | cut -d "|" -f 7 )
        echo "Completed backup for" $newsnap "@" $newbacky2ver "Elapsed time:" $SECONDS "seconds"
        echo $(date "+%Y_%m_%d_%H_%M_%S") $pendingsnap"|"$newbacky2ver "completed." "Elapsed time:" $SECONDS "seconds" >> $logspot
		        echo $pendingsnap >> $compsnaps".tmp"
    else
        echo "No matching prior snap for" $vm "creating new backup for" $pendingsnap "to" $logdir$date"_missing_snaps.log"
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Start new backup for" $pendingsnap >> $logspot
        SECONDS=0
        rbd diff --whole-object $pool/$pendingsnap --format=json > $pendingdiff;
        backy2 backup -s $pendingsnap -r $pendingdiff rbd://$pool/$pendingsnap $vm;
#        secs=$SECONDS
        newbacky2ver=$( backy2 -m ls $vm | tail -n  1 | cut -d "|" -f 7 )
        echo "Completed backup for" $pendingsnap "@" $newbacky2ver "Elapsed time:" $SECONDS "seconds"
        echo $(date "+%Y_%m_%d_%H_%M_%S") $pendingsnap"|"$newbacky2ver "completed." "Elapsed time:" $SECONDS "seconds" >> $logspot
        echo $pendingsnap >> $compsnaps".tmp"
    fi
done < $pendingsnaps

rm $compsnaps".old"

mv $compsnaps $compsnaps".old"
# rm $pendingsnaps

mv $compsnaps".tmp" $compsnaps

echo "All backups complete" in $pendingsnaps

echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete for" $pendingsnaps

echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete." >> $logspot
