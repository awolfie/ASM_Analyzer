# ASM_Analyzer.pl
ASM_Analyzer is a perl program that was written to automatically go through an assembly program written for a 8-bit Microchip PIC that has the Enhanced Mid-range core (49 Instructions).  It analyzes the banksel commands and makes sure that there are banksel commands for every instruction where it might be needed.  It keeps track of the bank that it is in from previous instructions and will add and remove bank selects as needed.  Anyone who knows anything about assembly knows that bank selects are one of the biggest pains and time wasters.  This program helps you make sure you have them where needed, but no more than is needed.

To run the program, you need to have a perl interpreter.  I used ActivePerl on my Windows 10 computer.

Currently you need to have the assembly file, map file and processor include file (provided by Microchip) in the same directory as ASM_Analyzer.  Your run the program with a command line like this:
perl ASM_Analyzer.pl -input inputFile.asm -map mapFile.map -include processorIncludeFile.inc

I have a few projects that I use this on, for those, I have written 2 batch files.  One to copy the files from the project over to the ASM_Analyzer directory, run the perl script, and then to automatically open WinMerge in order to see and reveiw (and edit if needed) the changes.  The second batch file is used to "accept" the changes by copying the modified file back to the project directory and doing a little clean up of files.

Basic rules are that anytime there is a label or a call instruction, the analyzer figures it does not know what bank you are in and will put a bank select before the next ram register instruction.  If you know for sure what bank you will be in at a label or call instruction then you can put a comment at the end of a line like this, `; [Bank ram_register_name]`.  Also, if you have a banksel that the Analyzer thinks should be removed that you decide should not be removed you can add a `; [keep banksel]` in the comments on that line and the analyzer will not remove it.

The analyzer can currently handle one level of conditional assembly directives (like "if-else" or "ifdef" directives).  After the exit from the directive the analyzer assumes that it does not know what bank it is in.  The if and the else start with it knowing what bank it was last in.

If it is not working right on a section of your assembly file there is a conditional print command built into the perl script.  At the time of this writing it is on line 181 in the ASM_Analyzer.pl file.  Just choose the start and end line you would like to see more detail on.

The analyzer code is not that long and is commented, feel free to look through it and see the details.

---
### Wish List:
I don't really have time to take this further, but if someone is really interested here are a few dreams I had.  First, it would be nice if this was integrated with the calling the assembler.  I assume this would not be too hard to add it to my batch file, but I also assume it would not be integrated with MPLAB.  Second, I thought it would be really cool to take statistics of ram registers that are used in the program adjacent to one-another and then suggest how to most efficiently organize your declared labels in banked ram, so as to reduce the number of banksel commands needed.

---
### Disclaimers:
* I am not a perl programmer.  I just had a colleague in the office who knew perl well and coached me through writing this idea I had.
* Test on a **copy** of your code and use at your own risk.  It works great on my code, but that is no guarantee that it will work right on the way you code.
* It would not be difficult to make this work for other PIC processors with different instructions.  The perl script can easily be edited to accommodate.

---
### Addendum \- Batch File example for calling ASM_Analyzer
```
copy ".\dist\default\production\mapFile.X.production.map" "..\ASM_Analyzer\"
copy ".\src\AssemblyFile.asm" "..\ASM_Analyzer\"
cd ..\ASM_Analyzer\
perl ASM_Analyzer.pl -input "AssemblyFile.asm" -map "mapFile.X.production.map" -include "p16F18876.inc"
PAUSE
"C:\Program Files (x86)\WinMerge\WinMergeU.exe" /x ".\AssemblyFile.asm" ".\AssemblyFile.asm.mod"
DEL "mapFile.X.production.map"
```