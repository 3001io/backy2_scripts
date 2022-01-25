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

start_time=$(date -u +%s)
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
fail="false"

#cat $compdir*.snaps > $compsnaps.tmp
#sort $compsnaps.tmp > $compsnaps
# Create sorted list of snaps to backup
cat $pendir*.conf > $pendingsnaps.tmp
sort $pendingsnaps.tmp > $pendingsnaps
rm $pendingsnaps.tmp

# Create/renew list of completed snap backups
backy2 -m ls | awk -F\| '{print $3,$6}' > $compsnaps

# move the node conf files to an "old" directory
mv $pendir*.conf $pendir"old/"

# Log progress
echo $(date "+%Y_%m_%d_%H_%M_%S") "Attempting to create diff file and backups of pending snaps in" $pendingsnaps >> $logspot
echo "Creating diff file and backups of pending snaps in" $pendingsnaps
echo ""
# Start process for each pending snap in /srv/backy2/pending/pending.snaps
while read -r pendingsnap; do
	# Reset the fail variable
	fail="false"
	# Trim the snap off to get the volume
	vm=${pendingsnap%@*}
	# Trim the volume off to get the snap
	newsnap=${pendingsnap#*@}

	#### Test to see if the volume was backed up in a previous round of backy2
if grep -Fq $vm $compsnaps; then

	# Test if an existing back up exists for this snap, if not, then proceed, if so, end if and do next vm
	if ! grep -Fq $pendingsnap $compsnaps; then

		#### Create an "oldsnap" to create an RBD diff file in /srv/backy2/diff using the last backup snap compared with "newsnap"
		# Get the last backed up snap for the volume. This method creates that "last backupd up snap" from the group that was gathered
		# when the process started and saved as $compsnaps.
		echo "creating diff file and backups for pending snap" $pendingsnap
        	compsnap=$( grep $vm $compsnaps | tail -n1 | awk '{print $1}' )
		# Trim the volume off to get the last backed up snap
		oldsnap=${compsnap#*@}
		# Create the name for the new/pending vm diff file
		pendingdiff=$diffdir$pendingsnap".diff"

        	echo $(date "+%Y_%m_%d_%H_%M_%S") "Creating diff file" $pendingdiff "for" $pendingsnap "compared to previous backed up snap" $compsnap >> $logspot
        	sleep 10
        	if	rbd diff --whole-object $pool/$pendingsnap --from-snap $oldsnap --format=json > $pendingdiff; then
        		echo "Diff file completed in" $pendingdiff
		else
			echo "Diff file creation failed for" $pendingdiff
			$fail="true"
		fi
		# If the diff file creation failed, add this snap to the failed snaps file, skip this backup, and add a log entry.
		if fail="false"; then
			# This method pulls the UUID from the compsnaps list gathered at the start of the backup process, so that
			# snaps created during the backup process don't get confused in this mix.
			lastbacky2UID=$( grep $vm $compsnaps | tail -n1 | awk '{print $2}' )
        		echo "Start backup for " $pendingsnap " using diff " $pendingdiff " compared to last backed up snap " $compsnap " UUID= " $lastbacky2UID
        		sleep 15
			# Use UID to create differential backy2 based on the pending snapshot.
        		echo $(date "+%Y_%m_%d_%H_%M_%S") "Start backup for" $pendingsnap >> $logspot
			SECONDS=0
			backy2 backup -s $pendingsnap -r $pendingdiff -f $lastbacky2UID rbd://$pool/$compsnap $vm;
			newbacky2UID=$( backy2 -m ls $vm | tail -n  1 | awk -F\| '{print $6}' )
        		echo $(date "+%Y_%m_%d_%H_%M_%S") "Completed backup for" $newsnap "@" $newbacky2UID "Elapsed time:" $SECONDS "seconds"
        		echo ""
        		echo $(date "+%Y_%m_%d_%H_%M_%S") $pendingsnap"|"$newbacky2UID "completed." "Elapsed time:" $SECONDS "seconds" >> $logspot
        		# reset variables
			newbacky2ver="0"
        		lastbacky2ver="0"
		fi
	else
		echo $(date "+%Y_%m_%d_%H_%M_%S") "A prior backup already exists for" $pendingsnap ", skipping this snap"
	fi
else
	### This option creates a new snap backup when no previous snap existed for this VM or VM drive.
        echo "No matching prior backup for" $vm ", creating new backup for" $pendingsnap "to" $logdir$date"_missing_snaps.log"
        echo $(date "+%Y_%m_%d_%H_%M_%S") "Start new backup for" $pendingsnap >> $logspot
        # Reset time for this process
	SECONDS=0
	# Create a new diff file from the unbacked up snap
        pendingdiff=$diffdir$pendingsnap".diff"
        rbd diff --whole-object $pool/$pendingsnap --format=json > $pendingdiff;
        backy2 backup -s $pendingsnap -r $pendingdiff rbd://$pool/$pendingsnap $vm;
	# Get the version UUID of the new backup
        newbacky2ver=$( backy2 -m ls $vm | tail -n  1 | awk -F\| '{print $6}' )
        echo "Completed backup for" $pendingsnap "@" $newbacky2ver "Elapsed time:" $SECONDS "seconds"
        echo ""
        echo $(date "+%Y_%m_%d_%H_%M_%S") $pendingsnap"|"$newbacky2ver "completed." "Elapsed time:" $SECONDS "seconds" >> $logspot
        echo $pendingsnap >> $compsnaps".tmp"
fi
done < $pendingsnaps

### Cleanup working files
mv $compsnaps $compdir"old/"

echo "All backups complete" in $pendingsnaps

end_time=$(date -u +%s)
elapsed_time=$((end_time-start_time))

echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete for" $pendingsnaps "in" $(date -u -d @${elapsed_time} +"%T") "seconds" 
echo $(date "+%Y_%m_%d_%H_%M_%S") "All backups complete for" $pendingsnaps "in" $(data -u -d @${elapsed_time}  +"%T") "seconds" >> $logspot

mv $pendingsnaps $compsnaps
