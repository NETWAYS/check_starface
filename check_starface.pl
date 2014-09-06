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
                  [-v|--verbose=<verbosity level>]
                  [-i|--ignore=<list_of_ports_to_ignore_separated_by_comma>]
                  [-h|--help] [-V|--version]
  
Checks a Starface Applience/PBX.

=head1 OPTIONS

=over 4

=item -t|--timeout=<timeout in seconds>

Time in seconds to wait before script stops.

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


use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case bundling);
use Pod::Usage;
use IPC::Open3;
use IO::Socket;

# define hardwarestates
my $RAID3ware = 0;
my $sirrixISDNcontroller = 0;
my $digiumISDNcontroller = 0;

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

sub getDigiumStatus {
	my $cmd = '/usr/sbin/asterisk -rx "dahdi show status"';
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
			"RETURNCODE : " . $rc  . "\n" .
			"OUTPUT     :\n" . $output if ($main::verbose >= 100);
	printResultAndExit(3, "UNKNOWN", "Error: asterisk system call failed with RC $rc.") unless ($rc == 0);
	return $output;
}


# Get number of calls for span/port
sub getDigiumSpanCalls {
	my $cmd = "/usr/sbin/asterisk -rx \"pri show span $_[0]\"";
	my ($output, $rc) = executeCommand($cmd);
	print	"COMMAND    : " . $cmd . "\n" .
		"RETURNCODE : " . $rc  . "\n" .
		"OUTPUT     :\n" . $output if ($main::verbose >= 100);
	$output = 0;
	my @showSpan=split(/\n/, $output);
	foreach (@showSpan) {
		if($_ =~ /^Total active-calls:(\d*) /) {
			$output = $1;
		} 
	}
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
    my $cmd = '/usr/bin/psql asterisk -c "select count(1) from cdr where calldate > now()- INTERVAL \'5 Minute\'"';
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
    my $cmd = '/bin/sipsak --nagios-code --sip-uri sip:nagioscheck@localhost';
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
    my $cmd = '/bin/df -Plk /';
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


# version string
my $version = '0.1';


# init command-line parameters
my $argvCnt					= $#ARGV + 1;
my $host					= "localhost";
my $community				= '';
my $timeout					= 0;
my $show_version			= undef;
our $verbose				= 0;
my $help					= undef;


# init left variables
my @msg                     = ();
my @critMsg					= ();
my @warnMsg					= ();
my @unknMsg					= ();
my @okMsg					= ();
my %msgHash                 = ( "OK" => \@okMsg, "WARNING" => \@warnMsg, "CRITICAL" => \@critMsg, "UNKNOWN" => \@unknMsg );

my @perfdata				= ();
my @ignorelist				= ();
my $exitVal					= undef;


# get command-line parameters
GetOptions(
   "t|timeout=i"			=> \$timeout,
   "v|verbose=i"			=> \$main::verbose,
   "i|ignore=s"				=> \$main::ignore,
   "V|version"				=> \$show_version,
   "h|help"					=> \$help,
) or pod2usage({
	-msg     => "\n" . 'Invalid argument!' . "\n",
	-verbose => 1,
	-exitval => 3
});


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
} elsif ($lspci =~ /ISDN.*B410 quad-BRI/) {
	$digiumISDNcontroller = 1;
}


###########################################################################################
# check ISDN channels sirrix

# open asterisk cli interface and get output of "Srx show layers"

if ($sirrixISDNcontroller) {
 	my %starface=();
	my $port;
	my @SrxShowLayers=split(/\n/, getSrxShowLayers);

	foreach( @SrxShowLayers ) {
		if (/l1=0x[0-9a-f]*: port=0x(....).*mode=(..).*act=(.),? st='?([^\s]*)'?/) {
			$port = hex($1);
			#mode (TE/NT), active flag (0/1), status string
			($starface{$port}{mode}, $starface{$port}{active}, $starface{$port}{l1status}) = ($2, $3, $4);
			if (($starface{$port}{active} == 1) and
				($starface{$port}{l1status} =~ /ACTIVATED/)) {
				$starface{$port}{nagiosstate} = 0;
				$starface{$port}{l1up} = 1;
			} else {
				$starface{$port}{nagiosstate} = 2;
				$starface{$port}{l1up} = 0;
			}
			$starface{$port}{calls} = 0; # initialize calls
		}
		if (/l2=0x[0-9a-f]*: tei=([ 0-9]*), uiq=., iq=., siq=(.), st='(.*)':/) {
			if (defined $port) {
				$starface{$port}{l2siq} = $2;
				$starface{$port}{l2status} = $3;
				#if (($starface{$port}{l2status} eq "ST_L2_70_MULTIPLE_FRAME_ESTABLISHED_NORMAL") or 
				#    ($starface{$port}{l2status} eq "ST_L2_1_TEI_UNASSIGNED") or
				#    ($starface{$port}{l2status} eq "ST_L2_4_TEI_ASSIGNED")) {
				if ($starface{$port}{l2siq} == 1) {
					$starface{$port}{nagiosstate} = 0;
                    $starface{$port}{l2up} = 1;
				}	
			}
		}
        if ((defined $port)
            and (defined $starface{$port}{l2status})
            and ($starface{$port}{active} == 0)
            and ($starface{$port}{l2status} eq "ST_L2_4_TEI_ASSIGNED")) {
                # no power on l1 is not necessarily an error
                $starface{$port}{nagiosstate} = 0;
        }
		if (defined $port and /occ=(.)/) {
			$starface{$port}{calls} += $1; # just a snapshot at this moment
		}
	}

	my $allcalls=0;
	my @statuscounter=(0,0,0,0); # array: (index=status, value=counter)
	my $ISDN_msg='';

	for $port (sort keys %starface ) {
		$allcalls+=$starface{$port}{calls};					# count active calls
		$statuscounter[$starface{$port}{nagiosstate}]+=1;	# count OKs, CRITICALs, ...
		if ( (grep(/$port/, @ignorelist)) ) {
			$starface{$port}{nagiosstate}=0;
			$starface{$port}{ignore}="ignore ";
		} else {
			$starface{$port}{ignore}="";
		}
		$ISDN_msg .= ", $starface{$port}{ignore}Port $port: $state[$starface{$port}{nagiosstate}]" if ($main::verbose >= 10);
		push (@{$msgHash{$state[$starface{$port}{nagiosstate}]}},
            "Port $port: L1:".($starface{$port}{l1up}?"UP":"DOWN").
            "(".$starface{$port}{l1status}.") ".
            "L2:".($starface{$port}{l2up}?"UP":"DOWN").
            "(".$starface{$port}{l2status}.") ");
		push (@perfdata, " Port_".$port."::calls=$starface{$port}{calls}");
	}

	if ($main::verbose >= 10) {
		unshift (@msg, "[ISDN: $statuscounter[0] OK, $statuscounter[2] CRITICAL$ISDN_msg, $allcalls active calls]");
	}
	push (@perfdata, "total::calls=$allcalls");

	my $ISDN_Chanels = scalar(keys %starface); 
	unshift (@perfdata, " ISDN_Channels=$statuscounter[0];;;0;$ISDN_Chanels");
} elsif ($digiumISDNcontroller) {
	my @DigiumShowStatus=split(/\n/, getDigiumStatus);
 	my %starface=();
	my $port;

	foreach( @DigiumShowStatus ) {
		if ($_ =~ /^B4XXP \(PCI\) Card ([0-9]) Span ([1-9]) \s*(\S*)/) {
			$port = $2;
			$starface{$port}{status} = $3;
			#print ("Port $port Status >$3<\n");
			if (($starface{$port}{status} eq "OK")) {
				$starface{$port}{nagiosstate} = 0;
				#print "nagios OK\n";
			} else {
				$starface{$port}{nagiosstate} = 2;
				#print "nagios NO\n";
			}
			$starface{$port}{calls} = 0; # initialize calls
			$starface{$port}{calls} = getDigiumSpanCalls($port);	
	 }
	}

	my $allcalls=0;
	my @statuscounter=(0,0,0,0); # array: (index=status, value=counter)
	my @ISDN_Critical=();
	my $ISDN_msg='';

	for $port (sort keys %starface ) {
		$allcalls+=$starface{$port}{calls};					# count active calls
		#print ("Nagiosstate: $starface{$port}{nagiosstate}\n");
		$statuscounter[$starface{$port}{nagiosstate}]+=1;	# count OKs, CRITICALs, ...
		if ( (grep(/$port/, @ignorelist)) ) {
			$starface{$port}{nagiosstate}=0;
			$starface{$port}{ignore}="ignore ";
		} else {
			$starface{$port}{ignore}="";
		}
		$ISDN_msg .= ", $starface{$port}{ignore}Port $port: $state[$starface{$port}{nagiosstate}]" if ($main::verbose >= 10);
		push (@{$msgHash{$state[$starface{$port}{nagiosstate}]}}, "Port $port: status: $starface{$port}{status}");
		push (@perfdata, " port_".$port."::calls=$starface{$port}{calls}");
	}
    
    if ($main::verbose >= 10) {
		unshift (@msg, "[ISDN: $statuscounter[0] OK, $statuscounter[2] CRITICAL$ISDN_msg, $allcalls active calls]");
	}
	push (@perfdata, "total::calls=$allcalls");

	my $ISDN_Chanels = scalar(keys %starface); 
	unshift (@perfdata, " ISDN_Channels=$statuscounter[0];;;0;$ISDN_Chanels");

} else {
	push (@okMsg, "no ISDN");
}

###########################################################################################
# check calls

my $lastCalls = getLast5minCalls;
$lastCalls =~ tr/\n/ /;
if ($lastCalls =~ /count\s*-------\s*(\d+)\s*\(1/) {
    $lastCalls = $1;
	print	"Last 5min Calls: $lastCalls.\n" if ($main::verbose >= 100);
	push (@okMsg, "$lastCalls calls in the last 5 minutes") if ($main::verbose >= 10);
	push (@perfdata, " 5min_calls=$lastCalls");
}


###########################################################################################
# check sip via sipsak

my ($SIPrc, $SIPconnect) = getSIP;
$SIPconnect =~ tr/\n/ /;
if ($SIPrc eq 2) {
	push (@critMsg, "$SIPconnect");
} elsif ($SIPrc eq 1) {
	push (@warnMsg, "$SIPconnect");
} elsif ($SIPrc eq 3) { 
	push (@unknMsg, "$SIPconnect");
} else {
	push (@okMsg, "$SIPconnect");
}


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
		push (@critMsg, "Webinterface: unknown response");
	} else {
		push (@okMsg, "Webinterface");
	}
	close $remote;
} else {
	unshift (@critMsg, "Webinterface: unable to connect");
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
		push (@critMsg, "Load $SysLoad1 $SysLoad5 $SysLoad15");
	} elsif ($SysLoad1>=$SysLoadW or $SysLoad5>=$SysLoadW or $SysLoad15>=$SysLoadW) {
		push (@warnMsg, "Load $SysLoad1 $SysLoad5 $SysLoad15");
	} else {
		push (@okMsg, "Load $SysLoad1 $SysLoad5 $SysLoad15");
	}
	push (@perfdata, "load1=$SysLoad1;$SysLoadW;$SysLoadC load5=$SysLoad5;$SysLoadW;$SysLoadC load15=$SysLoad15;$SysLoadW;$SysLoadC");
}


###########################################################################################
# check disk usage
# df -Pkl
#Dateisystem        1024-Blöcke   Benutzt Verfügbar Kapazit. Eingehängt auf
#/dev/mapper/VolGroup00-LogVol00  73641128   2431056  67408984       4% /

my $DiskUsage = getDiskUsage;
$DiskUsage =~ tr/\n/ /;
if ($DiskUsage =~ /\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)% \/ *$/) {
    my ($DiskCapa,$DiskUsed,$DiskFree,$PercentUsed) = ($1,$2,$3,$4);
	print	"DiskUsed: ${DiskUsed}kB, DiskFree: ${DiskFree}kB, DiskCapa: ${DiskCapa}kB, PercentUsed: $PercentUsed%.\n" if ($main::verbose >= 100);
	my ($PercentUsedW, $PercentUsedC) = (85, 95);
	if ($PercentUsed>=$PercentUsedC) {
		push (@critMsg, "DiskUsage: $PercentUsed% used");
	} elsif ($PercentUsed>=$PercentUsedW) {
		push (@warnMsg, "DiskUsage: $PercentUsed% used");
	} else {
		push (@okMsg, "DiskUsage: $PercentUsed%");
	}
    my $DiskWarn = int ($DiskCapa*($PercentUsedW/100));
    my $DiskCrit = int ($DiskCapa*($PercentUsedC/100));
	push (@perfdata, "Disk=${DiskUsed}kB;$DiskWarn;$DiskCrit;0;$DiskCapa");
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
		push (@critMsg, "RAID $RAIDStatus");
	} elsif ($RAIDStatus =~ /REBUILD/) {
		push (@warnMsg, "RAID $RAIDStatus");
	} else {
		push (@okMsg, "RAID $RAIDStatus");
	}
} else {
	push (@okMsg, "no RAID");
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



if ($#critMsg > -1) {
    $exitVal = 2;
} elsif ($#warnMsg > -1) {
    $exitVal = 1;
} elsif ($#unknMsg > -1) {
    $exitVal = 3;
} else {
    $exitVal = 0;
}



# print check result and exit
my $outExtended;
foreach my $state (keys %msgHash)
{
    foreach my $out (@{$msgHash{$state}})
    {
        $outExtended .= "[$state] $out\n";
    }
}
printResultAndExit($exitVal, $state[$exitVal], join(" ", @msg) . " " . join(" ", @critMsg) . " " . join(" ", @warnMsg) . " " . join(" ", @unknMsg) . " " . "\n$outExtended" . " | " . join(' ', @perfdata));


# vim: ts=4 shiftwidth=4 softtabstop=4 
#backspace=indent,eol,start expandtab
