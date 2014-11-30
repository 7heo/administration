
Build Owncloud Desktop Clients
==============================

Introduction
------------

These set of files can be used to build the desktop clients for ownCloud.
With makemac.sh -h or makewinlin.sh -h you will get a concise manpage with all the available options.
The scripts can install all needed dependencies, (cross) compile the desktop clients and code sign the installer files. With the help of these scripts its quiet easy to theme the clients.

makemac.sh should run on OSX 10.9, Mavericks that is.
IT PRODUCES AN CLIENT WITH AN ERROR WHEN BUILD ON YOSEMITE. This will be fixed in futere releases of Mirall.
makewinlin.sh should run on OpenSUSE 13.2 64 bit.
The scripts have no significant error checking. So, basicly you are on your own.

Installation
------------
Download or clone the scripts and run makemac.sh or makewinlin.sh in your terminal.

Further information
-------------------
If you want to build the Mac client you will have to install Packages on your building machine first. To implement the Sparkle updater you will have to install the Sparkle framework too. Read the documentation in the folder 'doc'.