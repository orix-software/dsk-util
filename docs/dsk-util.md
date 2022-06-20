# Command: dsk-util

### Disk image utility

This tool is useful to extract files from dsk file. You can extract it, and uses command line tool to use it. For
example, if you extract a basic program (.bas in FTDOS .dsk file), you can see it with « list » binary. If it’s
a .hrs/.hir file, you can read it with viewhrs file.
You can create a «/home/sedoric/ » folder and adds .dsk sedoric files in this folder
Some .dsk files are imported in sdcard.tgz. For sedoric, you can have a look to «/usr/share/sedoric/ » and for
ftdos : « /usr/share/ftdos »

## SYNOPSYS
+ dsk-util -f|-s file.dsk
+ dsk-util -h

## EXAMPLES
+ dsk-util -f ftdos.dsk
+ dsk-util -s sedoric3.dsk

List files from .dsk (sedoric)
+ /home/sedoric# dsk-util -s ls sed.dsk

Extract a file from sedoric .dsk file
+ /home/sedoric# dsk-util -s e sed.dsk myfile.hrs

Extract only .hrs files from sedoric .dsk file
+ /home/sedoric# dsk-util -s e sed.dsk *.hrs

## DESCRIPTION
**dsk-util** display the directory of a disk image file.

## OPTIONS
*  -h
                show this help message and exit
*  -f
                FTDOS disk image
*  -s
                Sedoric disk image

## SOURCE
https://github.com/orix-software/dsk-util

