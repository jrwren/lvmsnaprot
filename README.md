mongolvmsnapback
================

MongoDB sharded cluster LVM snapshot backup tool.

features
========

* LVM snapshot
* configurable archiving
* tries to validate each run as much as possible

replica set backup
==================

* Run this script with a CRON on a hidden node.

sharded cluster backup
======================

* Run this script with a CRON on one config server and one node member of each of your shards.
* The MongoDB balancer has to be stopped to be 100% sure you have valid snapshots.

disabling mongodb's balancer
============================

* option 1: run a CRON to run 'mongo --eval 'sh.stopBalancer'
* option 2: follow these instructions: http://docs.mongodb.org/manual/tutorial/manage-sharded-cluster-balancer/#sharding-schedule-balancing-window

contributions
=============

* send a pull request
