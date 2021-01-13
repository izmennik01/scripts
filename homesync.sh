#!/bin/bash

## Copy files back from the drive to local 
#rclone copy gdrive:/SYNC/work ~/work

## sync local up to cloud
rclone sync ~/work/ gdrive:/SYNC/work




