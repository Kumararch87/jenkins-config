#!/bin/bash
# Copyright (C) 2011 Citrix Systems, Inc.  All rights reserved
#     
# This software is licensed under the GNU General Public License v3 or later.
# 
# It is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or any later version.
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
# Version 3.0.0.2012-02-09T01:27:42Z

#set -x
 
usage() {
  printf "Usage: %s [vhd file in secondary storage] [template directory in secondary storage] [template local dir] \n" $(basename $0) 
}
options='tcp,soft,timeo=133,retrans=1'
cleanup()
{
  if [ ! -z $snapshotdir ]; then 
    umount $snapshotdir
    if [ $? -eq 0 ];  then
      rmdir $snapshotdir
    fi
  fi
  if [ ! -z $templatedir ]; then 
    umount $templatedir
    if [ $? -eq 0 ];  then
      rmdir $templatedir
    fi
  fi
}

if [ -z $1 ]; then
  usage
  echo "2#no vhd file path"
  exit 0
else
  snapshoturl=${1%/*}
  vhdfilename=${1##*/}
fi

if [ -z $2 ]; then
  usage
  echo "3#no template path"
  exit 0
else
  templateurl=$2
fi

if [ -z $3 ]; then
  usage
  echo "3#no template local dir"
  exit 0
else
  tmpltLocalDir=$3
fi


snapshotdir=/var/run/cloud_mount/$(uuidgen -r)
mkdir -p $snapshotdir
if [ $? -ne 0 ]; then
  echo "4#cann't make dir $snapshotdir"
  exit 0
fi

mount -o $options $snapshoturl $snapshotdir
if [ $? -ne 0 ]; then
  rmdir $snapshotdir
  echo "5#can not mount $snapshoturl to $snapshotdir"
  exit 0
fi

templatedir=/var/run/cloud_mount/$tmpltLocalDir
mkdir -p $templatedir
if [ $? -ne 0 ]; then
  templatedir=""
  cleanup
  echo "6#cann't make dir $templatedir"
  exit 0
fi

mount -o $options $templateurl $templatedir
if [ $? -ne 0 ]; then
  rmdir $templatedir
  templatedir=""
  cleanup
  echo "7#can not mount $templateurl to $templatedir"
  exit 0
fi

VHDUTIL="/opt/xensource/bin/vhd-util"

copyvhd()
{
  local desvhd=$1
  local srcvhd=$2
  local parent=
  parent=`$VHDUTIL query -p -n $srcvhd`
  if [ $? -ne 0 ]; then
    echo "30#failed to query $srcvhd"
    cleanup
    exit 0
  fi
  if [[ "${parent}"  =~ " no parent" ]]; then
    dd if=$srcvhd of=$desvhd bs=2M     
    if [ $? -ne 0 ]; then
      echo "31#failed to dd $srcvhd to $desvhd"
      cleanup
      exit 0
    fi
  else
    copyvhd $desvhd $parent
    $VHDUTIL coalesce -p $desvhd -n $srcvhd
    if [ $? -ne 0 ]; then
      echo "32#failed to coalesce  $desvhd to $srcvhd"
      cleanup
      exit 0
    fi
  fi
}

templateuuid=$(uuidgen -r)
desvhd=$templatedir/$templateuuid.vhd
srcvhd=$snapshotdir/$vhdfilename
copyvhd $desvhd $srcvhd
virtualSize=`$VHDUTIL query -v -n $desvhd`
physicalSize=`ls -l $desvhd | awk '{print $5}'`
cleanup
echo "0#$templateuuid#$physicalSize#$virtualSize"
exit 0
