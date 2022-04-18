#!/bin/bash
awk '
     /127\.127\.28\.0/ { sum += $5 * 1000; cnt++; }
     END { print sum / cnt; }
' </var/log/ntpstats/peerstats
