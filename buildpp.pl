#!/usr/bin/perl -w

# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.


use strict;
use Fcntl ':mode';
use Cwd;

my $workingDir = &Cwd::cwd();

#a mapping to find the path of a file
my %fileMapping=();

#a cache of level 1 dependencies
my %deps=();

#a cache of the recursive dependencies (also stored i .d files)
my %depCache=();

#a cache of file times -1 = file dos't exist, -2 = cache entry invalid
my %timeStamps=();

#a hash used to remember files pased for this run, also speeds up parsing
my %recurivePassedFiles=();

#a hash from files to modificaion times, for the O files that needs to be
#rebuild this run.
my %rebuildOFiles=();
#a has from filenames to compiler arguments for O files
my %rebuildOFilesArguments=();
#The O file currently being build
my $currentOFileNumber = 1;
#the total number of O files needing to be build
my $numberOfOFiles = -1;
#The time we started to compile files
my $compileStartTime = 0;

#a hash from files to modificaion times, for the exe files that needs to be
#rebuild this run.
my %rebuildExeFiles=();
#a has from filenames to linker arguments for exefiles
my %rebuildExeFilesArguments=();

my @exeFiles=();
my $doClean = 0;
my $doBuild = 0;
my $doTest = 0;
my $testArguments = "";
my @targets = ();

#the localbuild.pl file may modify the variables below

#A hash from regEx's for OS names to $target values
my %osHash = ("linux", "linux", "cygwin", "windows");

my $incDirs="-I. ";






#The current build target, empty for no specific target
my $target = "";

#Use lazy linking or not
my $lazyLinking = 0;

#The program to use as a compiler
my $compiler = "g++";
#The default flags used when compiling code into object files
my $cflags = "-c -Wall ";
#Defines the suffixes that if included with #include ""
#will become part of the dependencies. Used in a regEx therefore
#the weird syntax.
my $includeSuffix = "\\.h|\\.cpp";
#The suffix that your code files have, DON'T put a dot in front 
my $codeSuffix = "cpp";
#The suffix to put after object files, DON'T put a dot in front 
my $objectSuffix = "o";

#The program to use as a linker
my $linker = "g++";
#The default flags used when linking object files together
my $ldflags = "";
#The suffix to put after executable files, DON'T put a dot in front 
my $exeSuffix = "";

#The dir where buildit generates files (.o .exe and .d files)
#if it dos't exist it will be created. WARNING ALL files here
#will be deleted on clean! 
my $buildDir = "build/";

#If true you are requested to confirm when cleaning
my $cleanConfirm = 1;


#Colour definitions for different types of output
my $colourVerbose = "\033[33m";
my $colourNormal = "\033[37;40m";
my $colourError = "\033[33;41m";
my $colourAction = "\033[32m";
my $colourExternal = "\033[36m";
my $colourWarning = "\033[33m";
my $colourGirlie = "\033[35m"; 

#If false the colour entrys will not be used.
my $useColours = 0;

#Displays lots of information if true.
my $verbose = 0;

#If true displays information that you normally dont need nor want.
my $girlie = 0;

#If true show when we rebuild .d files.
my $showDBuild = 0;

#If true always shows the command used for compilation (else just on error)
my $showCompilerCommand = 0;

#If true always shows the command used for linking (else just on error)
my $showLinkerCommand = 0;

#Tries to reads an extra file and parse its contents, it will only
#generate a warning if it can't find it.
sub readConfigFile
{
  my ($filename) = @_;
  my $contents = "";
  my $config;
  if (open ($config, "$filename")) {
	print "reading $filename\n";
	while (<$config>) {
	    $contents .= $_;
	}
	close ($config);
    }
    else {
	print "Warning: unable to open $filename\n";
    }
    eval $contents;
    
    if (!($@ eq "")){
      die $@;
    }
}

#Tries to determine the OS we are running under and sets $target accordingly
sub autoTarget
{
  my $targetFound = 0;
  my $osMatch;
  my $osString;
  my $osName = $^O;  
  while (($osMatch, $osString) = each %osHash){
    if ($osName =~ /$osMatch/){
      $targetFound = 1;
      $target = $osString;
      last;
    }
  }
  
  
  if ($targetFound==0){
    print "WARNING: autoTarget failed to acquire a target for '$osName'\n";
    print "Try fixing %osHash or switch to manual targeting\n"
  }
}

readConfigFile("localbuild.pl");



if (!$exeSuffix eq ""){
    $exeSuffix = ".$exeSuffix";
}

#searcehs a dir for files that may be used to gennerate .o and exe files with
sub findFilesInDir
{
  my $dirName =  $_[0];
  $dirName =~ s/[\n\r]+$//;
  my $dir;
  opendir ($dir, $dirName)
    || die "Can't find directory '$dirName' specified in modulelist";
  
  my @entrys = readdir $dir;
  
  my $usableFiles = 0;
  
  foreach(@entrys){
    if ($_ !~ /^\.+$/){
      #it was not .. or .
      my $fileName = $dirName."/".$_;
      my $mode = (stat($fileName))[2];
      if (S_ISDIR($mode)){
        findFilesInDir($fileName);
      }
      else {
        if ($_ =~ /(^.*)($includeSuffix)$/){
          $usableFiles = 1;
          my $entry = $_;
          if (!exists($fileMapping{$entry})){
            $fileMapping{$entry} = $dirName."/";
            #print "found $entry in $dirName\n";
        }
      
        }
        elsif ($_ =~ /\.auto$/){
          my $name = $_;
          print $colourExternal."Updating $name in $dirName$colourNormal\n";
          chdir($dirName);
          print `./$name`;
          chdir($workingDir);
        }
      }
    }
  }
  closedir $dir;
  if ($usableFiles == 1){
    $incDirs = $incDirs."-I$dirName ";
  }
}

#reads the modulelist file and generates the search tables for building
sub readModuleList
{
  print $colourAction."Reading module list and compiling file list$colourNormal\n";
  open (moduleList, "<modulelist")
    || die "Can't open modulelist";
    
  while (<moduleList>){
    my $dirName = $_;
    findFilesInDir($dirName);
  }

  close moduleList;
}

#reads the commandline arguments
sub parseArguments
{
    foreach(@ARGV){
	if ($_ eq "-clean"){
	    $doClean = 1;
	}
  elsif ($_ eq "-verbose"){
    $verbose = 1;
  }
  elsif ($_ eq "-girlie"){
    $girlie = 1;
  }
elsif ($_ eq "-showdbuild"){
    $showDBuild = 1;
  }  
  elsif ($_ eq "-usecolours" or $_ eq "-usecolors"){
    $useColours = 1;
  }
	elsif ($_ =~ /^-test(.*)/){
	    $testArguments = $1;
	    $doTest = 1;
	}
	else {
	    my $argument = $_;
	    $argument =~ s/^.*\///;
	    #if (exists($fileMapping{$argument.".$codeSuffix"})){
		push(@targets, $argument);
	    #}
	    #else{
		#die "You are trying to build '$_' but I don't know ".
		 #   "anything about that component\n";
	   # }
	}
    }
    if (scalar(@targets) != 0 || ($doClean == 0)){
	$doBuild = 1;
    }
}

#generates a string that can be used to search the filelist for files that
#the user has requested a build of
sub makeMatchString
{
  my $match="";
  if (scalar(@targets) == 0){
    $match = ".*\.$codeSuffix";	
  }
  else {
    foreach (@targets){
      $match = $match.$_.".$codeSuffix|";
    }
    $match =~ s/\|$//;
  }
  return $match;
}

#removes the specified object files
sub removeObjectFiles
{
    print $colourAction."Removing object files$colourNormal\n";
    my $match = makeMatchString();
    foreach(keys(%fileMapping)){
	unlink(($fileMapping{$_}.$_.".".$objectSuffix));
    }
}



#gets the time stamp of the first argument (file (-path + sufix))
sub getTime
{
  my $filename = $_[0];
  my $result = -1;

  if (exists($timeStamps{$filename}) and $timeStamps{$filename} != -2){
    $result = $timeStamps{$filename};
  }
  else {
   my @fileStatus = stat($filename);
    if (scalar(@fileStatus) == 0){
      $result = -1;
    }
    else {
      $result = $fileStatus[9];    
    }
  }
  $timeStamps{$filename} = $result;

  return $result;
}

#parses a file and gennerates a parsed version in memory (only 1. level deps are
#generated, code files will also gennerate linker level 1. information
#first argument is the name of the file without path
sub parseFile
{
  my $filename = $_[0];

  if (exists($deps{$filename})){
    return;
  }

  if ($verbose){
    print $colourVerbose."Parsing file $filename".$colourNormal."\n";
  }

  if (!exists($fileMapping{$filename})){
    die $colourError."Unable to find file '$filename'".$colourNormal."\n";
  }
  my $filePath = $fileMapping{$filename}.$filename;

  #parse it 
  my $file;
  my @includeList=();
  my $currentTarget = "all";
  my $currentLazyLinking = $lazyLinking;

  open ($file, "<$filePath") 
		|| die "Unexpected error unable to read $filePath";

  while (<$file>){
    my $line = $_;  
    if ($line =~ /\/{2,3}\#target\s+(\S+)/){
      $currentTarget = $1;
    }
    if ($line =~ /\/{2,3}#lazylinking\s+(\S+)/){
      my $arg = $1;
      if ($arg =~ /off/i){
        $currentLazyLinking = 0;
      }
      if ($arg =~ /on/i){
        $currentLazyLinking = 1;
      }
    }
    if ($currentTarget eq "all" or $target eq $currentTarget){
      if ($line =~ /(\#include\s*\"\s*)(\S+)(\s*\")/){
        push (@includeList, $1.$2.$3);
        if ($currentLazyLinking){
          my $linkName = $2;
          #remove suffix
          $linkName =~ s/\.[^\.]+$//;
          push (@includeList, "\#link $linkName");
        }
      }
      if ($line =~ /\/{2,3}(\#\S+\s?\S*)\s*/){
        push (@includeList, ($1));
      }
    } 
  }
  close($file);
  
  $deps{$filename} = \@includeList;
}


#parses a given file recursivly returning a list of alle include and
#link dependencies
#returns a list of all dependencies
#first argument is the name of the file without path
sub parseFileRecurcive
{
  my $file = $_[0];
  my @result=();

  if (exists($recurivePassedFiles{$file})){
    return @result;
  }
  
  $recurivePassedFiles{$file} = "";
  
  parseFile($file);
  
  if (!exists($deps{$file})){
    die $colourError.
      "Trying to get recursive dependencie information for $file, ".
      "it has not been created$colourNormal\n";
  }

  my @dep = @{$deps{$file}};
  my %unique = ();
  @result = @dep;
  for my $item (@dep){
    if ($item =~ /\#link\s+(\S+)/){
      my $newFile = $1;
      parseFile($newFile.".$codeSuffix");
      my @subItem = parseFileRecurcive($newFile.".$codeSuffix");
      for my $subSubItem (@subItem){
        if ($subSubItem =~ /\#link/ || $subSubItem =~ /\#ldflags/){
          if (!exists($unique{$subSubItem})){
            push (@result, $subSubItem);
            $unique{$subSubItem} = " ";
          }
        }
      }
    }
    else{ if ($item =~ /\#include\s+\"\s*(\S+)\s*\"/){
      my $newFile = $1;
      parseFile($newFile);
      my @subItem = parseFileRecurcive($newFile);
      for my $subSubItem (@subItem){
        if (!exists($unique{$subSubItem})){
          push (@result, $subSubItem);
          $unique{$subSubItem} = " ";
        }
      }
    }}
  }
  return @result;
}


#gennerate .d file on disk (cached version of parseFile)
#includes all levels
#first argument is the name of the file without path
sub parseFileCached{
  my $filename = $_[0];
  
  if (exists($depCache{$filename})){
    my @result = @{$depCache{$filename}};
    return @result;
  }
  
  if ($verbose){
    print $colourVerbose."Testing $filename.d$colourNormal\n";
  }
  
  my $dFilename = $buildDir.$filename.".d";
  my $dTime = getTime($dFilename);
  my $fileTime = getTime($fileMapping{$filename}.$filename);
  
  my $rebuild = 0;
  
  if ($dTime == -1 or $dTime <= $fileTime){
    $rebuild = 1;
  }
  else {
    my $dFile;
    open ($dFile, "<$dFilename") ||
      die ($colourError."Unexpected error unable to open $dFilename for input".
           $colourNormal."\n");
    while (<$dFile>){
      my $line = $_;
      if ($line =~ /\#include\s+\"(\S+)\"/){
        my $depName = $1;
        if (!exists($fileMapping{$depName})){
          die ($colourError."Unknown file $depName$colourNormal\n");
        }
        my $depPath = $fileMapping{$depName};
        my $depTime = getTime($depPath.$depName);
        if ($depTime >= $dTime){
          $rebuild = 1;
          last();
        }
      }
      if ($line =~ /\#link\s+(\S+)/){
        my $depName = $1.".$codeSuffix";
        if (!exists($fileMapping{$depName})){
          die ($colourError."Unknown file $depName$colourNormal\n");
        }
        my $depPath = $fileMapping{$depName};
        my $depTime = getTime($depPath.$depName);
        if ($depTime >= $dTime){
          $rebuild = 1;
          last();
        }
      }
    }
  }
  
  my @deps = ();
  
  if ($rebuild){
    if ($showDBuild){
      print $colourAction."Building $filename.d$colourNormal\n";
    }
    
    @deps = parseFileRecurcive($filename);
    
    my $outFile;
    open ($outFile, ">$dFilename") ||
      die $colourError."Unable to write to $dFilename$colourNormal\n";
    
    for my $fileLine (@deps){
      print $outFile $fileLine."\n";
    }
    
    close ($outFile);
    $depCache{$filename} = \@deps;
    #invalidate timestamp of .d file
    $timeStamps{$dFilename} = -2;
  }
  else {
    my $dFile;
    open ($dFile, "<$dFilename") ||
      die ($colourError."Unexpected error unable to open $dFilename for input".
           $colourNormal."\n");
    
    while (<$dFile>){
      push (@deps, $_);
    }
    close($dFile);
  }
  
  return @deps;
}






#returns a string containing progress infor (only valid when compiling O files)
sub getProgressInfo
{
  my $timePassed = time()-$compileStartTime;
  my $result;
  if ($currentOFileNumber == 1){
    $result = "(0%"
  }
  else {
    my $progress = ($currentOFileNumber-1)*100/$numberOfOFiles;
    my $timeString;
    if (!($progress==0)){
      my $timeLeft = ($timePassed/($progress/100)-$timePassed);
      $timeLeft = int $timeLeft;
      if ($timeLeft > 60){
        my $minutes = int ($timeLeft/60);
        $timeString.=$minutes."m ";
        $timeLeft -= $minutes*60;
      }
      $timeString.=$timeLeft."s";
    }
    $progress = int ($progress);
    $result = "($progress% $timeString";
  }
  $result.=")";
  return $result;
}

#builds an object file
#first argument is the file without a path and without suffix
sub buildObjectFile
{
  my $filename = $_[0];  
    
  my $comileArguments = $rebuildOFilesArguments{$filename};
  my $path = $fileMapping{$filename.".$codeSuffix"};
  
  my $progress = getProgressInfo();
  my $command = "$compiler -o$buildDir$filename.$objectSuffix $comileArguments $path$filename.$codeSuffix";
  print $colourAction."$currentOFileNumber/$numberOfOFiles Compiling ".
        "$filename.o           $progress$colourNormal\n";
  
  if ($showCompilerCommand == 1){
      print "$command\n";
  }
  `$command`;
  if ($? != 0) {
    print $colourError."Compiling of $filename.$objectSuffix failed$colourNormal\n";
    if (!$showCompilerCommand){
      print "$command\n";
    }
    unlink($filename.".".$objectSuffix);
      die $colourError."   Sorry   $colourNormal\n";
  }
  #invalidate object files timestamp cache
  $timeStamps{$buildDir.$filename.".$objectSuffix"} = -2;
  $currentOFileNumber++;
}

#builds an object file
#first argument is the code file to use l
sub findObjectFiles
{
  my $filename = $_[0];

  if ($verbose){
    print $colourVerbose."Generating $filename.$objectSuffix$colourNormal\n";
  }

  if (!exists($fileMapping{$filename.".$codeSuffix"})){
    die $colourError."Tryed to compile $filename.$codeSuffix file not found".
      "$colourNormal\n";
  }

  my $codeTime = getTime($fileMapping{$filename.".$codeSuffix"}.
                         $filename.".$codeSuffix");
  my $objTime = getTime($buildDir.$filename.".$objectSuffix");
  
  my $needsRebuild = 0;

  if ($objTime == -1 or $objTime <= $codeTime){
    $needsRebuild = 1;
    if ($girlie){
      print $colourGirlie."You have rearranged $filename.$codeSuffix now I ".
      "need to recompile $filename.$objectSuffix!$colourNormal\n";
    }
  }


  my $path = $fileMapping{$filename.".$codeSuffix"};
 
  %recurivePassedFiles = ();
  my @includeList = parseFileCached($filename.".$codeSuffix");

  for my $incFile (@includeList){
    if ($incFile =~ /\#include\s+\"\s*(\S+)\s*\"/){
      $incFile = $1;
      if (!exists($fileMapping{$incFile})){
        die $colourError."Could not find $incFile$colourNormal\n";
      }
      my $incTime = getTime($fileMapping{$incFile}.$incFile);
      if ($incTime >= $objTime){
        $needsRebuild = 1;
        if ($girlie){
          print $colourGirlie."You keep changing $incFile now I ".
          "need to recompile $filename.$objectSuffix!$colourNormal\n";
        }
        last();
      }
    }
  }


  if ($needsRebuild){
    %recurivePassedFiles = ();
    my @linkList = parseFileCached($filename.".$codeSuffix");
    my $linkLine = "$filename.$objectSuffix";
    my %linkMap = ();
    my $myCFlags = $cflags;
  
    for my $item (@linkList){
      if ($item =~ /^#cflags\s+(.*)\s*/){
        $myCFlags = $myCFlags." $1";
      }
    }

    $rebuildOFiles{$filename}=0;
    $rebuildOFilesArguments{$filename}="$myCFlags $incDirs";
    #buildObjectFile($filename);
  }
}

#builds an exe file
#first argument is the file without a path and without suffix
sub buildExeFile
{
  my $filename = $_[0];
  my $arguments = $rebuildExeFilesArguments{$filename};

  my $command = "$linker -o$buildDir$filename$exeSuffix $arguments";
  
  print $colourAction."Linking $filename$exeSuffix$colourNormal\n";
  
  if ($showLinkerCommand == 1){
    print "$command\n";
  }
  `$command`;
  if ($? != 0) {
    print $colourError."Linking of $filename$exeSuffix failed$colourNormal\n";
    if (!$showLinkerCommand){
      print "$command\n";
    }
    unlink($filename.$exeSuffix);
      die $colourError."   Sorry   $colourNormal\n";
  }
  $timeStamps{$buildDir.$filename."$exeSuffix"} = -2;
}

#finds the files requered for an exe file, from a file path without suffix
sub findExeFiles
{
  my $filename = $_[0];

  findObjectFiles($filename);

  my $exeTime = getTime($buildDir.$filename."$exeSuffix");
  my $objTime = getTime($buildDir.$filename.".$objectSuffix");
  
  my $needsRebuild = 0;

  if ($exeTime == -1 or $exeTime <= $objTime){
    $needsRebuild = 1;
    if ($girlie){
      print $colourGirlie.
      "Uhh $filename$exeSuffix is younger than ".
      "$filename.$objectSuffix relinking will be required $colourNormal\n";
    }
  }

  %recurivePassedFiles = ();
  my @linkList = parseFileCached($filename.".$codeSuffix");
  my $isExe = 0;
  my $linkLine = "$buildDir$filename.$objectSuffix";
  my %linkMap = ();
  $linkMap{"$filename.$objectSuffix"} = " ";
  my $myLdFlags = $ldflags;
  #filter list to contain only valid data
  my @filterList;
  for my $item (@linkList){
    if ($item =~ /^#link\s+(\S+)\s*/){
      my $oFile = $1;
      my $objFile = $oFile.".$objectSuffix";
      if (!exists($linkMap{$objFile})){
        $linkMap{$objFile}=" ";
        findObjectFiles($oFile);
        $objTime = getTime($buildDir.$objFile);
        if ($exeTime <= $objTime){
          $needsRebuild = 1;
          if ($girlie){
            print $colourGirlie."Do you like this new object file $objFile?".
            " Well lets relink $filename$exeSuffix$colourNormal\n";
          }
        }        
        $linkLine = $linkLine." $buildDir$objFile"
      }
    }
    if ($item =~ /^#ldflags\s+(.*)\s*/){
      $myLdFlags = $myLdFlags." $1";
    }
    if ($item =~ /^#exe/){
      $isExe = 1;
    }
  }

  if ($needsRebuild and $isExe){
    $rebuildExeFilesArguments{$filename}=" $linkLine $myLdFlags";
    $rebuildExeFiles{$filename}=-1;
    #buildExeFile($filename);
  }
}
    

#ensures that the build directory exists
sub buildDirTest
{
  my @fileStatus = stat($buildDir);
  if (scalar(@fileStatus) == 0){
    print $colourAction."Creating build dir$colourNormal\n";
    mkdir($buildDir);
  }
}

#tries to find the files that needs rebuild
sub scanForRebuildFiles
{
  my $match = makeMatchString();
  foreach(keys(%fileMapping)){
    if ($_ =~ /^($match)$/){
      my $theFile = $_;
      $theFile =~ s/\.$codeSuffix$//;
      findExeFiles($theFile);
    }
  }

}

#builds the files requested
sub buildFiles
{
  buildDirTest();
  print $colourAction."Finding files needing to be rebuild$colourNormal\n";

  scanForRebuildFiles();
  foreach (keys %rebuildOFiles){
    my $file=$_;
    my $path = $fileMapping{"$file.$codeSuffix"};
    $rebuildOFiles{$file}=getTime("$path$file.$codeSuffix");
  }
  
  print $colourAction."Building files$colourNormal\n";
  my @sorted;
  @sorted = sort {$rebuildOFiles{$b} cmp  $rebuildOFiles{$a}}keys%rebuildOFiles;
  $numberOfOFiles=$#sorted+1;
  $compileStartTime = time();
  for my $file (@sorted){
    buildObjectFile($file);
  }
  
  scanForRebuildFiles();
  print $colourAction."Linking files$colourNormal\n";
  for my $file (keys %rebuildExeFiles){
    buildExeFile($file);
  }

}

sub testFiles
{
    for my $file (@targets){
      print $colourAction."Testing $file$colourNormal\n";
      print `$buildDir$file $testArguments`;
    } 
}

$ENV{"target"}=$target;

parseArguments();

if (!$useColours){
  $colourVerbose = "";
  $colourNormal = "";
  $colourError = "";
  $colourAction = "";
  $colourExternal = "";
  $colourWarning = "";
  $colourGirlie = "";
}

readModuleList();

if ($doClean == 1){
  my $proceedWithClean = 1;
  print $colourWarning."Cleaning build directry '$buildDir'";
  if ($cleanConfirm){
    print ", are you sure? Yes or no: ";
    my $answer = <STDIN>;
    if (!($answer eq "Yes\n")){
      $proceedWithClean = 0;
      die $colourWarning."Clean aborted$colourNormal\n";
    }
    else {
      print "Proceeding with clean action"
      
    }
    print "$colourNormal\n"
  }
  else {
    print "$colourNormal\n";
  }
  
  my $dir;
  if ($proceedWithClean && !opendir ($dir, $buildDir)) {
    print "Can't find build directory '$buildDir' unable to clean";
  }
  else {
    my @entrys = readdir $dir;
    
    foreach(@entrys){
      if ($_ !~ /^\.+$/){
        #it was not .. or .
        unlink($buildDir."/$_");
      }
    }
    closedir $dir;
  }
}

if ($doBuild == 1){
  buildFiles();
}
if ($doTest){
  testFiles();
}
