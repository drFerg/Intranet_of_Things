Intranet_of_Things
==================

A secure Intranet of Things protocol for TinyOS.


Use
===

Thing
-----
To compile a Thing and install it onto a TelosB mote:
1 - Configure the Makefile to specify the node's attributes
2 - Run make telosb install.<node ID> bsl,/dev/ttyUSB<node usb addr>

Controller + Cache 
------------------
To use the controller and connect to the Cache, follow instructions above and then:
1 - Run java net.tinyos.sf.SerialForwarder -comm serial@/dev/ttyUSB<node usb addr>:telosb
2 - cp a copy of the HW Cache into client/
3 - Compile and run ./cache -p 1234 -c cache.conf
4 - cd .. and Run java KnotClient tempAutomaton.gapl
5 - Wait for the client to register with the Cache, hit q to query for devices and wait


Generate new Certificates
------------------------
To generate new certificates:
1 - cd to certgen, install onto a mote as above
2 - compile and run java show_genKeys -comm serial@/dev/ttyUSB<node usb addr>
3 - view the printout and copy required keys/pkc into Thing code.
