#!/usr/bin/perl -w
#
# COPYRIGHT:
#
# This software is Copyright (c) 2008 NETWAYS GmbH, Birger Schmidt
#                                <info@netways.de>
#      (Except where explicitly superseded by other copyright notices)
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from http://www.fsf.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.fsf.org.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to NETWAYS GmbH.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# this Software, to NETWAYS GmbH, you confirm that
# you are the copyright holder for those contributions and you grant
# NETWAYS GmbH a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# Nagios and the Nagios logo are registered trademarks of Ethan Galstad.


=head1 NAME

check_starface.pl - Nagios-Check Plugin for STARFACE Comfortphoning Equipment

=head1 SYNOPSIS

check_starface.pl [-t|--timeout=<timeout in seconds>]
		  [-p|--pgpassword=<PostGRESQL password for asterisk user>]
                  [-v|--verbose=<verbosity level>]
                  [-i|--ignore=<list_of_ports_to_ignore_separated_by_comma>]
                  [-h|--help] [-V|--version]

Checks a Starface Applience/PBX.

=head1 OPTIONS

=over 4

=item -t|--timeout=<timeout in seconds>

Time in seconds to wait before script stops.

=item -p|--pgpassword=<PostGRESQL password for asterisk user>

Password for user asterisk in PostGRESQL. Only necessary, if set during installation.

=item -v|--verbose=<verbosity level>

Enable verbose mode (levels: 1,2).
   1  : show each port status
   10 : show active calls at the moment of the check

=item -i|--ignore=<list_of_ports_to_ignore_separated_by_comma>

Which ports sould be ignored if not OK.
To ignore port zero and one but care about the others: 0,1

=item -V|--version

Print version an exit.

=item -h|--help

Print help message and exit.

=cut

package main;
use 5.010001;
use strict;
use warnings;
#use Getopt::Long qw(:config no_ignore_case bundling);
use Getopt::Long;
use Pod::Usage;
use IPC::Open3;
use IO::Socket;

# define hardwarestates
my $RAID3ware = 0;
my $sirrixISDNcontroller = 0;

# define states
our @state = ('OK', 'WARNING', 'CRITICAL', 'UNKNOWN');

sub printResultAndExit {

	# print check result and exit

	my $exitVal = shift;

	#print 'check_starface: ';

	print "@_" if (defined @_);

	print "\n";

	# stop timeout
	alarm(0);

	exit($exitVal);
}

# version string
my $version = '0.2';

# init command-line parameters
my $argvCnt				= $#ARGV + 1;
my $host				= "localhost";
my $community				= '';
my $timeout				= 0;
my $show_version			= undef;
our $verbose				= 0;
my $help				= undef;
my $pgpassword				= "asterisk";

# init left variables
my @msg					= ();
my @perfdata				= ();
my @ignorelist				= ();
my $exitVal				= undef;


# get command-line parameters
GetOptions(
   "t|timeout=i"			=> \$timeout,
   "p|pgpassword=s"			=> \$pgpassword,
   "v|verbose=i"			=> \$main::verbose,
   "i|ignore=s"				=> \$main::ignore,
   "V|version"				=> \$show_version,
   "h|help"				=> \$help,
) or pod2usage({
	-msg     => "\n" . 'Invalid argument!' . "\n",
	-verbose => 1,
	-exitval => 3
});

unless( defined $pgpassword ) {
	pod2usage(
        	-msg            => "\n$0 - Postgresql password:  \n",
        	-verbose        => 1,
	);
}
 
pod2usage(
	-msg		=> "\n$0" . ' - version: ' . $version . "\n",
	-verbose	=> 1,
	-exitval	=> 3,
) if ($show_version);

pod2usage(
#	-msg		=> "\n" . 'No host specified!' . "\n",
	-verbose	=> 2,
	-exitval	=> 3
) if ($help);


if ($main::ignore) {
	@ignorelist = split(/,/, $main::ignore);
	print "IGNOREPORTS: @ignorelist\n" if ($main::verbose >= 100);
}

# set timeout
local $SIG{ALRM} = sub {
	print 'check_starface: UNKNOWN: Timeout' . "\n";
	exit(3);
};
alarm($timeout);



sub executeCommand {
	my $command = join ' ', @_;
	($_ = qx{$command 2>&1}, $? >> 8);
}

sub getlspci {
# lspci
#
# ISDN controller: Unknown device affe or 2e1 (rev 03)
# RAID bus controller: 3ware Inc 3ware Inc 3ware 7xxx/8xxx-series PATA/SATA-RAID (rev 01)
#
    my $cmd = '/sbin/lspci';
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
			"RETURNCODE : " . $rc  . "\n" .
			"OUTPUT     :\n" . $output if ($main::verbose >= 100);
    printResultAndExit(3, "UNKNOWN", "Error: lspci system call failed with RC $rc.") unless ($rc == 0 or $rc == 127);
	return $output;
}

sub getSrxShowLayers {
	my $cmd = '/usr/sbin/asterisk -rx "Srx show layers"';
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
			"RETURNCODE : " . $rc  . "\n" .
			"OUTPUT     :\n" . $output if ($main::verbose >= 100);
	printResultAndExit(3, "UNKNOWN", "Error: asterisk system call failed with RC $rc.") unless ($rc == 0);
	return $output;
}

sub getLast5minCalls {
# calls
# psql asterisk -c "select count(1) from cdr where calldate > now()- INTERVAL '5 Minute'"
#   count
# -------
#      2
# (1 Zeile)
    my $cmd = "PGPASSWORD=".$pgpassword." /usr/bin/psql -U asterisk -w -c \"select count(1) from cdr where calldate > now()- INTERVAL \'5 Minute\'\"";
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
		"RETURNCODE : " . $rc  . "\n" .
		"OUTPUT     :\n" . $output if ($main::verbose >= 100);
	printResultAndExit(3, "UNKNOWN", "Error: psql system call failed with RC $rc.") unless ($rc == 0);
	return $output;
}

sub get3wareStatus {
# 3wareRAID status check
#
# Unit  UnitType  Status         %RCmpl  %V/I/M  Stripe  Size(GB)  Cache  AVrfy
# ------------------------------------------------------------------------------
# u0    RAID-1    OK             -       -       -       74.5294   ON     -
#
# Port   Status           Unit   Size        Blocks        Serial
# ---------------------------------------------------------------
# p0     OK               u0     74.53 GB    156301488     5RA3VMA1
# p1     OK               u0     74.53 GB    156301488     5RA3V44C
#
	if ($RAID3ware) {
		my $cmd = '/opt/3ware_cli/bin/tw_cli /c0 show';
		my ($output, $rc) = executeCommand($cmd);
		print	"COMMAND    : " . $cmd . "\n" .
				"RETURNCODE : " . $rc  . "\n" .
				"OUTPUT     :\n" . $output if ($main::verbose >= 100);
		printResultAndExit(3, "UNKNOWN", "Error: tw_cli system call failed with RC $rc.") unless ($rc == 0 or $rc == 127);
		return $output;
	} else {
		return '';
	}
}

sub getSIP {
# SIP connect via sipsak
# sipsak --nagios-code -vv --sip-uri sip:nagioscheck@localhost
    my $cmd = '/usr/bin/sipsak --nagios-code --sip-uri sip:nagioscheck@localhost';
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
		"RETURNCODE : " . $rc  . "\n" .
		"OUTPUT     :\n" . $output if ($main::verbose >= 100);
    printResultAndExit(3, "UNKNOWN", "Error: sipsak system call failed with RC $rc.") unless ($rc == 0);
	return ($rc, $output);
}

sub getDiskUsage {
# disk usage
# df -Plk
    my $cmd = '/bin/df -Plk';
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
			"RETURNCODE : " . $rc  . "\n" .
			"OUTPUT     :\n" . $output if ($main::verbose >= 100);
    printResultAndExit(3, "UNKNOWN", "Error: df system call failed with RC $rc.") unless ($rc == 0);
	return $output;
}

sub getSystemLoad {
# cat /proc/loadavg
# 0.01 0.01 0.00 1/169 10958
	my $filename = "/proc/loadavg";
	my $output;
	if (open my $in, "<", $filename) {
		#local( $/, *FH );
		$output = <$in>;
		# no need to explicitly close the file
	} else {
    	printResultAndExit(3, "UNKNOWN", "Error: Could not open $filename. $!");
	}
	return $output;
}



###########################################################################################
#
# main
#

my $lspci = getlspci;
$lspci =~ tr/\n/ /;
if ($lspci =~ /RAID.*3ware/) {
    $RAID3ware = 1;
}
if ($lspci =~ /ISDN.*(Sirrix|affe:)/) {
    $sirrixISDNcontroller = 1;
}


###########################################################################################
# check ISDN channels sirrix

# open asterisk cli interface and get output of "Srx show layers"

if ($sirrixISDNcontroller) {
 	my %starface=();
	my $port;
	my @SrxShowLayers=split(/\n/, getSrxShowLayers);

	foreach( @SrxShowLayers ) {
		if ((/^l1=0x.......: port=0x(....), type=BRI, mode=(..), ptp=., ma=., act=(.), st='(.*)'$/) or (/l1=0x.......: port=0x(....) type=BRI mode=(..) ptp=. syncAllowed=. act=(.) st=(.*) starting=. restarting=. started=.$/)) {
			$port = hex($1);
			#mode (TE/NT), active fag (0/1), status string
			($starface{$port}{mode}, $starface{$port}{active}, $starface{$port}{l1status}) = ($2, $3, $4);
			if (($starface{$port}{mode} eq "NT") and
				($starface{$port}{active} == 1) and
				($starface{$port}{l1status} eq "ST_L1_IPAC_G3_ACTIVATED")) {
				$starface{$port}{nagiosstate} = 0;
				#print "nagios OK\n";
			} else {
				$starface{$port}{nagiosstate} = 2;
				#print "nagios NO\n";
			}
			$starface{$port}{calls} = 0; # initialize calls
		}
		if (/^    l2=0x.......: tei=(...), uiq=., iq=., siq=., st='(.*)':/) {
			if (defined $port) {
				$starface{$port}{l2status} = $2;
				if ($starface{$port}{l2status} eq "ST_L2_70_MULTIPLE_FRAME_ESTABLISHED_NORMAL") {
					$starface{$port}{nagiosstate} = 0;
					#print "nagios OK\n";
				}
			}
		}
		if (defined $port and /occ=(.)/) {
			$starface{$port}{calls} += $1; # just a snapshot at this moment
		}
	}

	$exitVal = 0; # ok til now
	my $allcalls=0;
	my @statuscounter=(0,0,0,0); # array: (index=status, value=counter)
	my @ISDN_Critical=();
	my $ISDN_msg='';

	for $port (sort keys %starface ) {
		$allcalls+=$starface{$port}{calls};					# count active calls
		$statuscounter[$starface{$port}{nagiosstate}]+=1;	# count OKs, CRITICALs, ...
		if ( !(grep(/$port/, @ignorelist)) ) {
			$starface{$port}{ignore}="";
			if ($starface{$port}{nagiosstate} eq 2) {
				$exitVal = 2; # set global critical
				push (@ISDN_Critical, "Port $port");
			}
		} else {
			$starface{$port}{ignore}="ignore ";
		}
		$ISDN_msg .= ", $starface{$port}{ignore}Port $port: $state[$starface{$port}{nagiosstate}]" if ($main::verbose >= 10);
		push (@perfdata, "ISDN Port $port: $state[$starface{$port}{nagiosstate}], $starface{$port}{calls} calls");
	}

	if ($main::verbose >= 10) {
		unshift (@msg, "[ISDN: $statuscounter[0] OK, $statuscounter[2] CRITICAL$ISDN_msg, $allcalls active calls]");
	} elsif ($exitVal eq 2) {
		unshift (@msg, "[ISDN CRITICAL: " . join (', ', @ISDN_Critical) . "]");
	}
	push (@perfdata, "sum active calls: $allcalls");

	my $ISDN_Chanels = scalar(keys %starface);
	unshift (@perfdata, "ISDN Channels:" .
		" $state[0]:$statuscounter[0]/" . $ISDN_Chanels . # OK
		" $state[2]:$statuscounter[2]/" . $ISDN_Chanels   # CRITICAL
	);
} else {
	$exitVal = 0; # ok til now
	push (@msg, "ISDN: no");
}

###########################################################################################
# check calls

my $lastCalls = getLast5minCalls;
$lastCalls =~ tr/\n/ /;
if ($lastCalls =~ /count\s*-------\s*(\d+)\s*\(1/) {
    $lastCalls = $1;
	print	"Last 5min Calls: $lastCalls.\n" if ($main::verbose >= 100);
	push (@msg, "[$lastCalls calls in the last 5 minutes]") if ($main::verbose >= 10);
	push (@perfdata, "last 5min calls: $lastCalls");
}


###########################################################################################
# check sip via sipsak

my ($SIPrc, $SIPconnect) = getSIP;
$SIPconnect =~ tr/\n/ /;
if ($exitVal ne 2 and $SIPrc eq 2) {
	$exitVal = 2; 		# set global critical
	unshift (@msg, "[SIP CRITICAL: $SIPconnect]");
} elsif ($exitVal ne 1 and $SIPrc eq 1) {
	$exitVal = 1;		# set global warning if not already critical
	unshift (@msg, "[SIP WARNING: $SIPconnect]");
} elsif ($exitVal ne 3 and $SIPrc eq 3) {
	$exitVal = 3;		# set global warning if not already critical
	unshift (@msg, "[SIP UNKNOWN: $SIPconnect]");
} else {
	push (@msg, "[SIP OK: $SIPconnect]") if ($main::verbose >= 10);
}
push (@perfdata, "$SIPconnect");


###########################################################################################
# check http

my $document = "/";
my $remote = IO::Socket::INET->new( Proto	=> "tcp", PeerAddr  => $host, PeerPort  => "http(80)",);
if ($remote) {
	$remote->autoflush(1);
	print $remote "GET $document HTTP/1.0\015\012\015\012";
	my $http_answer = join(' ', (<$remote>));
	$http_answer =~ tr/\n/ /;
	print	"COMMAND    : GET $document HTTP/1.0\n" .
			"OUTPUT     :\n" . $http_answer if ($main::verbose >= 100);
	unless ($http_answer =~ /STARFACE VoIP Software/) {
		unshift (@msg, "[Webinterface CRITICAL: unknown response]");
		push (@perfdata, "Webinterface CRITICAL: unknown response");
		$exitVal = 2; # set global critical
	} else {
		push (@msg, "[Webinterface OK]") if ($main::verbose >= 10);
		push (@perfdata, "Webinterface OK");
	}
	close $remote;
} else {
	unshift (@msg, "[Webinterface CRITICAL: unable to connect]");
	push (@perfdata, "Webinterface CRITICAL: unable to connect");
	$exitVal = 2; # set global critical
}


###########################################################################################
# check load
# cat /proc/loadavg
# 0.01 0.01 0.00 1/169 10958

my $SystemLoad = getSystemLoad;
$SystemLoad =~ tr/\n/ /;
if ($SystemLoad =~ /(\d+.\d+)\s*(\d+.\d+)\s*(\d+.\d+)\s*/) {
    my ($SysLoad1,$SysLoad5,$SysLoad15) = ($1,$2,$3);
	print	"Load: $SysLoad1 $SysLoad5 $SysLoad15.\n" if ($main::verbose >= 100);
	my ($SysLoadW, $SysLoadC) = (0.85, 0.95);
	if ($SysLoad1>=$SysLoadC or $SysLoad5>=$SysLoadC or $SysLoad15>=$SysLoadC) {
		unshift (@msg, "[load CRITICAL: $SysLoad1 $SysLoad5 $SysLoad15]");
		$exitVal = 2; # set global critical
	} elsif ($SysLoad1>=$SysLoadW or $SysLoad5>=$SysLoadW or $SysLoad15>=$SysLoadW) {
		unshift (@msg, "[load WARNING: $SysLoad1 $SysLoad5 $SysLoad15]");
		$exitVal = 1 if ($exitVal ne 2); # set global warning if not already critical
	} else {
		push (@msg, "[load: $SysLoad1 $SysLoad5 $SysLoad15]") if ($main::verbose >= 10);
	}
	push (@perfdata, "load: $SysLoad1 $SysLoad5 $SysLoad15");
}


###########################################################################################
# check disk usage
# df -Pkl
#Dateisystem        1024-Blöcke   Benutzt Verfügbar Kapazit. Eingehängt auf
#/dev/mapper/VolGroup00-LogVol00  73641128   2431056  67408984       4% /

my $DiskUsage = getDiskUsage;
$DiskUsage =~ tr/\n/ /;
if ($DiskUsage =~ /\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)% \/$/) {
    my ($DiskCapa,$DiskUsed,$DiskFree,$PercentUsed) = ($1,$2,$3,$4);
	print	"DiskUsed: ${DiskUsed}kB, DiskFree: ${DiskFree}kB, DiskCapa: ${DiskCapa}kB, PercentUsed: $PercentUsed%.\n" if ($main::verbose >= 100);
	my ($PercentUsedW, $PercentUsedC) = (85, 95);
	if ($PercentUsed>=$PercentUsedC) {
		unshift (@msg, "[DiskUsage CRITICAL: $PercentUsed% used, ${DiskFree}kB free]");
		$exitVal = 2; # set global critical
	} elsif ($PercentUsed>=$PercentUsedW) {
		unshift (@msg, "[DiskUsage WARNING: $PercentUsed% used, ${DiskFree}kB free]");
		$exitVal = 1 if ($exitVal ne 2); # set global warning if not already critical
	} else {
		push (@msg, "[DiskUsage: $PercentUsed%]") if ($main::verbose >= 10);
	}
	push (@perfdata, "DiskUsed: ${DiskUsed}kB, DiskFree: ${DiskFree}kB, DiskCapa: ${DiskCapa}kB, PercentUsed: $PercentUsed%");
}


###########################################################################################
# check 3wareRAID
#get3wareStatus
# u0    RAID-1    OK             -       -       -       74.5294   ON     -

my $RAIDStatus = get3wareStatus;
$RAIDStatus =~ tr/\n/ /;
if ($RAIDStatus =~ /\u0    RAID-1    (OK|REBUILD.*|DEGRADED)/) {
	print	"RAID Status: $RAIDStatus.\n" if ($main::verbose >= 100);
    $RAIDStatus = $1;
	if ($RAIDStatus eq "DEGRADED") {
		unshift (@msg, "[RAID CRITICAL: $RAIDStatus]");
		$exitVal = 2; # set global critical
	} elsif ($RAIDStatus =~ /REBUILD/) {
		unshift (@msg, "[RAID WARNING: $RAIDStatus]");
		$exitVal = 1 if ($exitVal ne 2); # set global warning if not already critical
	} else {
		push (@msg, "[RAID: $RAIDStatus]") if ($main::verbose >= 10);
	}
	push (@perfdata, "RAID: $RAIDStatus");
} else {
	push (@msg, "[RAID: no]") if ($main::verbose >= 10);
	push (@perfdata, "RAID: no");
}


###########################################################################################
# check asterisk run time
#
# ps -o etime=,tty= -C asterisk
#   04:19:18 ?
#      58:26 pts/1
# [[dd-]hh:]mm:ss
# ^(..)[ -](..)[ :](\d\d):(\d\d) \?$
# my ($days,$houres,$min,$sec)=($1,$2,$3,$4);



# print check result and exit
printResultAndExit($exitVal, $state[$exitVal], join(' - ', @msg) . "|" . join(';', @perfdata));


# vim: ts=4 shiftwidth=4 softtabstop=4
#backspace=indent,eol,start expandtab
