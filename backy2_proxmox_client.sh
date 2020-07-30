#!/bin/bash
#
# Copyright (c) 2019-2020 herb Garcia herbgarcia3001@gmail.com>
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

#This script creates CEPH snapshots of proxmox virtual machine disks stored on RBD
#It snapshots each disk using year, month, time as the "@" location
#It logs the snapshot names in a log file in the /var/log/backy2 directory then copies that file to the
#backy2 server in a ".conf" file named for the source hostname and date/time.

logdir="/var/log/backy2/"
date=$(date "+%Y_%m_%d")
logname="backy2proxmox_"$date".log"
logspot="$logdir""$logname"
snaplist=$logdir$HOSTNAME"_"$date"_snaps.log"
backy2host="10.10.160.61"
backy2hostfile="/srv/backy2/pending/"$HOSTNAME"_"$date".conf"
failed=$logdir$date"failed.list"
isrunning=0
#   Run through all virtual machine configuration files on this node
#   and check how many disks are a block storage on the ceph for each virtual machine and save the name of the block


for file in /etc/pve/local/qemu-server/*.conf; do
     fname=`basename "$file"`
     vmnum=${fname%.conf}
     vmdisk=$(rbd ls vmhdd | grep $vmnum)


    if [[ $(qm status $vmnum) = *running ]]; then
        isrunning=1
        qm stop $vmnum
        echo "qm status" $vmnum
        echo $(date "+%Y_%m_%d_yT%H_%M_%S") $vmnum "shutting down" >> $logspot
        sleep 20
        secs=0
        until [[ $(qm status $vmnum) = *stopped ]]; do
           echo "Please wait for" $vmnum "to shutdown"
           sleep 10
           secs=$((secs+10))
           if (( $secs >= "600" )); then
               echo $vmnum "failed to shutdown"
               echo $vmnum >> $failed
               secs=0
               break
            fi
        done
    fi


    echo $vmnum "is stopped and ready for snapshot"
    echo $(date "+%Y_%m_%d_yT%H_%M_%S") $vmnum "is stopped and ready for snapshot" >> $logspot
    backup="snap_"$(date "+%Y_%m_%d_%H_%M")
    echo "start weekly proxmox snapshot of" $vmnum"@"$backup
    echo $(date "+%Y_%m_%d_%H_%M_%S") $vmnum"@"$backup "started" >> $logspot
    qm snapshot $vmnum $backup;
    vmdisk=$(rbd ls vmhdd | grep $vmnum)
    
    for i in $vmdisk; do
            echo $i"@"$backup >> $snaplist
            echo $i"@"$backup "finished"
            echo $(date "+%Y_%m_%d_%H_%M_%S") $i"@"$backup "finished" >> $logspot
    done
    
    sleep 10
    qm status $vmnum
    echo $(date "+%Y_%m_%d_%H_%M_%S") $(qm status $vmnum) >> $logspot

    if [ $isrunning = "1" ]; then
        qm start $vmnum
        echo "qm start" $vmnum
        echo $(date "+%Y_%m_%d_yT%H_%M_%S") $vmnum "starting" >> $logspot
        until [[ $(qm status $vmnum) = *running ]]; do
            sleep 10
            echo $vmnum "status: stopped"
        done
        echo $vmnum "status: running"
        echo $(date "+%Y_%m_%d_yT%H_%M_%S") $vmnum "is running" >> $logspot
        isrunning=0
    fi

done

if ps -p $SSH_AGENT_PID > /dev/null; then
    echo "ssh-agent is already running"
    # Do something knowing the pid exists, i.e. the process with $PID is running
else
    eval `ssh-agent -s`
fi

scp $snaplist $backy2host":"$backy2hostfile &&
echo "${backy2hostfile##*/}" "created on" $backy2host
# rm $snaplist
echo $(date "+%Y_%m_%d_yT%H_%M_%S") "snapshot process complete on this node" >> $logspot
echo "All snapshots complete on this node"
