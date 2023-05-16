check_starface
==============

Check Plugin for STARFACE Comfortphoning Equipment. Checks a Starface Appliance/PBX.

## Required Perl Libraries 
                           
* IPC::Open3
* IO::Socket
    
### Usage

    check_starface.pl [-t|--timeout=<timeout in seconds>]
    [-v|--verbose=<verbosity level>]
    [-i|--ignore=<list_of_ports_to_ignore_separated_by_comma>] [-h|--help]
    [-V|--version]

    Checks a Starface Applience/PBX.

Options:

    -t|--timeout=<timeout in seconds>
        Time in seconds to wait before script stops.

    -v|--verbose=<verbosity level>
        Enable verbose mode (levels: 1,2). 1 : show each port status 10 :
        show active calls at the moment of the check

    -i|--ignore=<list_of_ports_to_ignore_separated_by_comma>
        Which ports sould be ignored if not OK. To ignore port zero and one
        but care about the others: 0,1

    -V|--version
        Print version an exit.

    -h|--help
        Print help message and exit.
