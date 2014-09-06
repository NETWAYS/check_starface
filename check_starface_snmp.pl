#!/usr/bin/perl
# 
# # log in to your starface and create the directory 
# mkdir -p /opt/nagios/bin/
# # copy check_starface.pl onto the appliance:
# scp check_starface.pl root@starface:/opt/nagios/bin/check_starface.pl
# # make sure it is executabe:
# chmod +x /opt/nagios/bin/check_starface.pl
# # open the firewall for snmp requests and reboot
# echo "INSERT INTO iptablesrule(iptableschainid, startportnumber,endportnumber, target, clientip, protocoltype) VALUES (1,161,0,'ACCEPT','ALL', 'udp');" | psql asterisk
# reboot
#

use strict;
use Net::SNMP;
my $host_name = shift;
my ($session, $error) = Net::SNMP->session(
   -hostname  => $host_name,
   -community => 'public',
   -port      => 161,
   -timeout   => 2,
);

if (!defined($session)) {
   printf("ERROR: %s.\n", $error);
   exit 2;
}

#.1.3.6.1.4.1.32354.1.2.999.3.1.4.9.98.117.108.107.99.104.101.99.107 = INTEGER: 0
#.1.3.6.1.4.1.32354.1.2.999.4.1.2.9.98.117.108.107.99.104.101.99.107.1 = STRING: "OK |ISDN Channels: OK:1/1 CRITICAL:0/1;ISDN Port 3: OK, 0 calls;sum active calls: 0;last 5min calls: 0;SIP ok ;Webinterface OK;load: 0.00 0.00 0.04;RAID: no"

my $output_id = ".1.3.6.1.4.1.32354.1.2.999.4.1.2.9.98.117.108.107.99.104.101.99.107.1";
my $state_id = ".1.3.6.1.4.1.32354.1.2.999.3.1.4.9.98.117.108.107.99.104.101.99.107";
my $output = $session->get_request(
   -varbindlist => [$output_id]
);
my $state = $session->get_request(
   -varbindlist => [$state_id]
);
if (!defined($state)) {
   printf("ERROR: %s.\n", $session->error);
   $session->close;
   exit 2;
}
printf("%s\n",
   $output->{$output_id}
);
$session->close;
exit $state->{$state_id};
