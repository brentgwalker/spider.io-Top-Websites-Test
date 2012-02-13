#!/usr/bin/perl -w
#
# Brent Walker, Feb. 2012.
# List "bugs" (tracking links, etc.) found on top 100,000 websites.
# Uses daily list of 1,000,000 top websites from Alexa.com.
# Uses bugs database from ghostery.com.
#
use IO::Uncompress::Unzip qw(unzip $UnzipError);
use Test1;

$numberWebsites = 100000;

$verbose = 0;

# Download list of websites from Alexa.
$alexaBaseUrl = "http://s3.amazonaws.com/alexa-static";
$alexaZipFile = "top-1m.csv.zip";

downloadFile("${alexaBaseUrl}/${alexaZipFile}",$alexaZipFile,$verbose);

# Unzip file.
$alexaCSVFile = $alexaZipFile;
$alexaCSVFile =~ s/.zip$//;

unless (-e ${alexaCSVFile} ) {
    my $status = unzip $alexaZipFile => $alexaCSVFile
	or die "unzip failed: ${UnzipError}\n";
}

@websites = getTopWebsites($alexaCSVFile,$numberWebsites);

# Get bugs database from ghostery.com.
$bugsDBUrl = "http://www.ghostery.com/update/all?format=json";
$bugsDBFile = "bugs.js";
downloadFile($bugsDBUrl,$bugsDBFile,$verbose);

# Extract bugs.
@globalBugList = getBugs($bugsDBFile,$verbose);

# For each bug, get page from apps subdirectory of ghostery.com.
$ghosteryUrlBase = "http://www.ghostery.com/apps";
foreach my $bug (@globalBugList) {
    downloadFile("${ghosteryUrlBase}/" . bugToWeb($bug), bugToFile($bug) . ".html",$verbose);
}

# Extract data from bug files.
foreach my $bug (@globalBugList) {
    $globalBugData{$bug} = processGhosteryFile(bugToFile($bug) . ".html");
}

# Cross-reference between examples found for the bugs and the list of top websites.
%newBugList = crossReference(@globalBugList,%globalBugData,@websites);

printBugs($numberWebsites,%newBugList);

exit(0);
