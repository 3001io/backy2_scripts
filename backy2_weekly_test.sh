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


# Set variables

logdir="/var/log/backy2/"
snapdate=$(date "+%Y_%m_%d")
logname="backy2proxmox_"$snapdate".log"
logspot="$logdir""$logname"
snaplist=$logdir$HOSTNAME"_"$snapdate"_snaps.log"
backy2host="10.10.160.61"
backy2hostfile="/srv/backy2/pending/"$HOSTNAME"_"$snapdate".conf"

#   Run through all virtual machine configuration files on this node
#   and check how many disks are a block storage on the ceph for each virtual machine and save the name of the block

for file in /etc/pve/local/qemu-server/*.conf; do
     fname=`basename "$file"`
     vmnum=${fname%.conf}

#   Create a snapshot of the virtual machine blocks and name the snap location as the date, down to seconds
#   Save the snapshot name in a list.

        backup="snap_"$(date "+%Y_%m_%d_%H_%M")
        echo "start weekly proxmox snapshot of" $vmnum"@"$backup
        echo $(date "+%Y_%m_%d_%H_%M_%S") $vmnum"@"$backup "started" >> $logspot
        qm snapshot $vmnum $backup;
        echo $vmnum"@"$backup "finished"
        echo $(date "+%Y_%m_%d_%H_%M_%S") $vmnum"@"$backup "finished" >> $logspot
        vmdisk=$(rbd ls vmhdd | grep $vmnum)
        For $i in $vmdisk; do echo $vmdisk"@"$backup >> $snaplist; done
        
#   if the virtual machine was running, restart the virtual machine. 

        sleep 30
        if [[ $isrunning = "1" ]]; then    
            qm start $vmnum
            echo "qm start" $vmnum
            echo $(date "+%Y_%m_%d_yT%H_%M_%S") $vmnum "starting" >> $logspot
            until [[ $(qm status $vmnum) = *running ]]; do
                sleep 10
                echo $vmnum "status: stopped"
            done
            echo $vmnum "status: running"
            echo $(date "+%Y_%m_%d_%H_%M_%S") $vmnum "is running" >> $logspot
            isrunning=0
        fi
        
#   End snapshot activities        
        
done

#   If the ssh-agent is not running, start it

if ps -p $SSH_AGENT_PID > /dev/null; then
   echo "ssh-agent is already running"
   # Do something knowing the pid exists, i.e. the process with $PID is running
else
eval `ssh-agent -s`
fi

#   Copy the list of snapshots to the backy2 server

scp $snaplist $backy2host":"$backy2hostfile &&
echo "${backy2hostfile##*/}" "created on" $backy2host
# rm $snaplist
echo $(date "+%Y_%m_%d_%H_%M_%S") "snapshot process complete on this node" >> $logspot
echo "All snapshots complete on this node"
