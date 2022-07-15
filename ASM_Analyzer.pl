#!perl

use strict;
use Getopt::Long;


my $inputFile;
my $mapFile;
my $includefile;
GetOptions('input=s' => \$inputFile,
           'map=s' => \$mapFile,
           'include=s' => \$includefile);

# print "\n\n$inputFile $mapFile\n\n";
if (!(defined($inputFile) && defined($mapFile) && defined($includefile) && -f $inputFile)) {
    print "Usage: $0 -input inputFile.asm -map mapFile.map -include processorIncludeFile.inc\n";
	exit(0);
}

my $lineNumber = 0;
my $lastBanksel = 0;
my $lastBankselLabel = '';
my $bankSelCounter = 0;

my @instructions = ('ADDWF','ADDWFC','ANDWF','ASRF','LSLF','LSRF','CLRF','COMF','DECF','INCF','IORWF','MOVF','MOVWF','RLF','RRF','SUBWF','SUBWFB','SWAPF','XORWF','DECFSZ','INCFSZ','BCF','BSF','BTFSC','BTFSS','MOVFW','TSTF','BTF','STORE');

my @skipIntructions = ('DECFSZ','INCFSZ','BTFSC','BTFSS','SKPZ','SKPNZ','SKPC','SKPNC','SKPNEG','SKPPOS','SKPNEXT');

my %labelAddrHash = ();
my %isLabel = ();

# open map file to parse for RAM registers and program labels
open(MAP, $mapFile) || die("Couldn't open mapFile: $mapFile");
 my $sectionActive = 0;
while (my $mapLine = <MAP>) {
    chomp($mapLine);
    # Specify where in the map file to start looking for addresses
    if ($mapLine =~ /Symbols - Sorted by Address/) {
        $sectionActive = 1;
    }
    # Find labels, their addresses and their memory location type
    if ($sectionActive && $mapLine =~ /^\s*(\S+)\s+(\S+)\s+(\S+)/) {
        my ($label, $addr, $location) = ($1, $2, $3);
        if ($location eq 'data') {
            # store data label addresses
            $labelAddrHash{$label} = $addr;
        } elsif ($location eq 'program') {
            # indicate program labels as labels
            $isLabel{$label} = 1;
        }
    }
}
close(MAP);

# open include file to parse for processor defined RAM registers
open(INCLUDE, $includefile) || die("Couldn't open includefile: $includefile");
$sectionActive = 0;
while (my $includeLine = <INCLUDE>){
    chomp($includeLine);
    if ($includeLine =~ /Bank/) {
        $sectionActive = 1;
    }
    if ($includeLine =~ /Bits/) {
        $sectionActive = 0;
    }
    if ($sectionActive && $includeLine =~ /^\s*(\S+)\s+\S+\s+\D+(\S{4})/) {
        my ($label, $addr) = ($1, $2);
        $labelAddrHash{$label} = $addr;
    }
}

open(IN, $inputFile);
my @lines = (<IN>);
close(IN);

my $BankselAdd = 0;
my $BankselRemove = 0;
my $BankselReplace = 0;
my $lastBank = -1;
my $isSkipInstruction = 0;
my $lastLineWasSkip =0;
my $seenBanksel = 0;
my $seenBankLabel = "";
my $seenBankLine = 0;
# used to store state when entering an if statement to use for else statement
my $enterIfseenBankLabel = 0;
my $enterIfseenBankLine = 0;
my $enterIfseenBanksel = 0;
my $enterIflastBank = 0;

my $inputLine = 1;

for (my $i=0; $i<=$#lines; $i++) {
    # If line is a comment, skip it
    if ($lines[$i] =~ /^\s*;/) {
        $inputLine++;
        next;
    }
    if ($lines[$i] =~ /^\s*(\S+)\s/) {  #   look for the first blob of characters on the line
        my $labelOrInstr = $1;
        if ($isLabel{$labelOrInstr}) {
            # If it is marked as a label reset the bank to unknown unless a bank is designated in the comments.
            # e.g. "[bank ram_register_name]"
            if (($lines[$i] =~ /\[bank\s+(\w+)\]/i)) {
                $lastBank = getBank($1);
                print "$inputLine Bank designated with label, Bank: $lastBank\r\n";
            } else {
                $lastBank = -1;
            }
            $seenBanksel = 0;           # Clear that any banksel has been seen
        } else {
            $lastLineWasSkip = $isSkipInstruction;  # Copy whether the previous instruction is able to skip this instruction
            my $isFregInstruction = 0;      # If not, see if it matches an instruction in the list that modifies a file register
            foreach my $instr (@instructions) { 
                if ($labelOrInstr =~ /$instr/i) {
                    $isFregInstruction = 1;         # it is an instruction in the list. Indicate we need to evaluate this line.
                    last;
                }
            }
            foreach my $instr (@skipIntructions) {
                if ($labelOrInstr =~ /$instr/i){
                    $isSkipInstruction = 1;         # record that it is an instruction that can skip the next instruction.
                    last;
                } else {
                    $isSkipInstruction = 0;
                }
            }
            # if it is a call (or lcall) instruction, clear the last bank seen to unknown, unless bank returned in is designated.
            # e.g. "[bank ram_register_name]"
            if ($lines[$i] =~ /^\s+l?call\s+/i) {
                if (($lines[$i] =~ /\[bank (\w+)\]/i)) {
                    $lastBank = getBank($1);
                    print "$inputLine Return bank designated with call, Bank: $lastBank\r\n";
                } else {
                    $lastBank = -1;
                }
            }
            # if bank select instruction is seen take note of the line number it is on and the label and indicate that the bank select has been seen.
            if ($lines[$i] =~ /^\s+banksel\s+(\S+)/i) {
                if ($lastLineWasSkip == 1) {
                    print "$inputLine Found banksel with a conditional skip as the previous instruction! Removing it.\r\n";
                    splice @lines,$i,1;
                    $seenBanksel = 0;   # seen Banksel has been removed, indicate not seen.
                    $i--;
                    $BankselRemove++;
                    next;
                } else {
                    if ($seenBanksel == 1){
                        if (($lines[$seenBankLine] =~ /\[keep\s+banksel]/i)){
                            # Don't remove the banksel if there is a "[keep banksel]" in the comments.
                            print "$inputLine Keep banksel command found, not removing banksel.\r\n";
                        } else {
                            print "$inputLine Previous banksel was never used. Removing it.\r\n";
                            splice @lines,$seenBankLine,1;
                            $i--;
                            $BankselRemove++;
                        }
                    }
                    $seenBankLabel = $1;
                    $seenBankLine = $i;
                    $seenBanksel = 1;
                }
            }
            # look for "if" statements in the assembly file.  When they are found store the seen bank information so it can be restored if an "else" statement is found too.
            if ($lines[$i] =~ /^\s+if?/) {
                $enterIfseenBankLabel = $seenBankLabel;
                $enterIfseenBankLine = $seenBankLine;
                $enterIfseenBanksel = $seenBanksel;
                $enterIflastBank = $lastBank;
            }
            if ($lines[$i] =~ /^\s+else\s+/) {
                $seenBankLabel = $enterIfseenBankLabel;
                $seenBankLine = $enterIfseenBankLine;
                $seenBanksel = $enterIfseenBanksel;
                $lastBank = $enterIflastBank;
            }
            # if an endif statement is found, assume we don't know what bank we are in
            if ($lines[$i] =~ /^\s+endif\s+/) {
                $lastBank = -1;
            }
            # for debugging... put the range of the input assembly file that you want more detail on in the lines below so they will print in the console to evaluate more closely.
            if (($inputLine >= 14730) && ($inputLine <= 0)){
                print "$inputLine $seenBanksel $lastBank $lastLineWasSkip: $lines[$i]";
            }
            # If this line has an instruction that edits the file register, then check the bank state
            if ($isFregInstruction) {
                my $instrLabel = "";
                if ($lines[$i] =~ /$labelOrInstr\s+([^\s,\r]+)/) {
                    $instrLabel = $1;       # store the label that the file register instruction is operating on.
                }
                if ($instrLabel ne "") {
                    my $bank = getBank($instrLabel);    # determine the PIC bank that the file register falls into
                    if ($bank == -1) {
                        # This instruction is in an unbanked section of RAM, if banksel was seen for this instruction it is not needed
                        if (($seenBanksel) && ($bank == getBank($seenBankLabel))) {
                            print "$inputLine Seen banksel for this nobank instruction ($seenBankLabel).\r\n";
                            splice @lines,$seenBankLine,1;
                            $seenBanksel = 0;   # seen Banksel has been removed, indicate no longer seen.
                            $i--;
                            $BankselRemove++;
                        }
                    } elsif ($bank >= 0) {
                        # This instruction is in a banked section of RAM, determine if the bank selection is available.
                        if ($lastBank == $bank) {
                            # Already in the right bank, no bank select needed
                            # If banksel was seen for this instruction, it is not needed. Remove it.
                            if ($seenBanksel) {
                                if (($lines[$seenBankLine] =~ /\[keep\s+banksel]/i)){
                                  # Don't remove the banksel if there is a "[keep banksel]" in the comments.
                                  print "$inputLine Keep banksel command found, not removing banksel.\r\n";
                                } else {
                                  print "$inputLine Already in the correct bank for this instruction ($seenBankLabel,$bank).\r\n";
                                  splice @lines,$seenBankLine,1;
                                  $seenBanksel = 0;   # seen Banksel has been removed, indicate no longer seen.
                                  $i--;
                                  $BankselRemove++;
                                }
                            }
                        } else {
                            # We are not already in the right bank, we need a bank select
                            if ($seenBanksel) {
                                # Bank select has already been seen
                                if (!($seenBankLabel eq $instrLabel)) {
                                    # Banksel found is not for this label, remove it.
                                    print "$inputLine Banksel found is not for this label, replace it\r\n";
                                    splice @lines,$seenBankLine,1;
                                    $lines[$i] =~ /^(\s*)/;
                                    splice @lines,$seenBankLine,0,"$1banksel\t$instrLabel\n";
                                    $BankselReplace++; 
                                }
                            } elsif (!($lines[$i] =~ /\[no bank add\]/)) {
                                # To force an exeption at this line, "[no bank add]" can be added to a line to ignore the needed banksel addition.
                                # Otherwise add a banksel in directly preceeding this line.
                                $lines[$i] =~ /^(\s*)/;
                                if ($lastLineWasSkip) {
                                    print "$inputLine WARNING - banksel needed but previous instruction was a conditional skip! NEEDS MANUAL ATTENTION!\r\n";
                                } else {
                                    print "$inputLine No banksel found, add it in\r\n";
                                    splice @lines,$i,0,"$1banksel\t$instrLabel\n";
                                    $i++;
                                    $BankselAdd++;
                                }
                            } else {
                                print "$inputLine Banksel needed, but told not to add it\r\n";
                            }
                            $lastBank = $bank;
                        }
                        $seenBanksel = 0;
                    }
                }
            }
            # if it is an instruction that conditionally skips the next instruction mark it as such.
            if (($lines[$i] =~ /^\sbtfs\w*\s+/) || ($lines[$i] =~ /^\sskp\w*\s+/)) {
                $lastLineWasSkip = 1;
            } else {
                $lastLineWasSkip = 0;
            }
        }
    }
    $inputLine++;
}

print "\r\n$BankselAdd Bank selects should be added.\r\n";
print "$BankselRemove Bank selects should be removed.\r\n";
print "$BankselReplace Bank selects replaced.\r\n";


open(OUT, ">$inputFile.mod");
foreach my $line (@lines) {
    print OUT $line;
}
close(OUT);


sub getBank() {
    my ($label) = @_;
    my $addr = $labelAddrHash{$label};
    if ($addr) {
        my $addrTrunc = hex($addr) & 0x7f;
        my $bank = (hex($addr) & 0xff80) >> 7;
        if ($addrTrunc > 0xB && $addrTrunc < 0x70) {
            return $bank;
        }
        return -1;
    } else {
        return -1;
    }
}
