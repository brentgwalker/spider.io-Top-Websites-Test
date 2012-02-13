package Test1;

use strict;
use LWP::Simple;

require Exporter;

use vars qw(@ISA @EXPORT $VERSION);

$VERSION = 0.01;

@ISA = qw(Exporter);
@EXPORT = qw(downloadFile getTopWebsites getUnique processGhosteryFile
             slurpFile getBugs bugToWeb bugToFile crossReference
             printBugs
          );

#=====================================================================
# Download specified URL to specified local file name.
#=====================================================================
sub downloadFile ($$$) {
    
    my $inURL = shift;
    my $localFile = shift;
    my $verbose = shift;

    if ( -e "${localFile}") {
	print "File ${localFile} already exists: not downloading.\n" if $verbose;
    }
    else {
	print "Downloading ${localFile} ...." if $verbose;
	my $status = getstore($inURL,$localFile);
	unless (is_success($status)) {
	    die "Couldn't download page: ${inURL}, status: ${status}";
	}
	print "done.\n" if $verbose;
    }
}

#=====================================================================
# Get specified number of websites from Alexa CSV file.
#=====================================================================
sub getTopWebsites ($$) {
    
    my $file = shift;
    my $number = shift;
    
    local *FIN;
    
    open(FIN, "<${file}")
	or die "Couldn't open file ${file}";
    
    my $numberRead=0;
    my @websites = ();
    while ( defined($_ = <FIN>) && ($numberRead < $number) ) {
	chomp;
	push(@websites,(split /,/, $_ )[1]);
	$numberRead++;
    }
    
    close (FIN);
    
    # Write file with top websites.
    local *FOUT;
    
    my $topSitesFile = "top${number}.txt";
    open(FOUT,">${topSitesFile}")
	or die "Couldn't open ${topSitesFile}: $!";
    
    foreach my $website (@websites) {
	print FOUT "${website}\n";
    }
    
    close(FOUT);
    
    return @websites;
}

#=====================================================================
# Return unique array.
#=====================================================================
sub getUnique (@) {
    
    my @input = @_;
    
    my %seen = ();
    my @output = ();
    
    # Get unique entries.
    foreach my $bug ( @input ) {
	next if $seen{$bug}++;
	push @output, $bug;
    }
    
    return @output;
}

#=====================================================================
# Process bug file from ghostery.com.
#=====================================================================
sub processGhosteryFile ($) {
    
    # Break down the extraction of data from the webpage into a few parts.
    # For anything more complicated, should probably use a proper HTML parser.
    
    my $tmpFileData = slurpFile($_[0]);
    
    my @bugdata = ();
    
    # Find website owning bug - in some cases there is no website listed for the bug.
    $tmpFileData =~ m/<h2>Website:<\/h2>.*?<a href="(.*?)" rel="nofollow">/s;
    if (length($1)) {
	push @bugdata,$1;
    }
    else {
	push @bugdata,"None listed";
    }

    # First get name and number of sites on which bug appears.
    if ($tmpFileData =~ m/<h3>(.*)<\/h3>.*?was found on over.*?<h3>(.*?)<\/h3>.*sites/s) {
	
	# Store number of sites the bug appears on.
	my $occurrences = $2;
	
	push @bugdata, $occurrences; 

	# Now get just the part of the text that contains examples.
	$tmpFileData =~ /Here's a sample:.*<div>(.*?)<\/div>/s;
	$tmpFileData = $1;
	
	# Extract the example website names.
	my @examples = $tmpFileData =~ m/<li class="shorten" id="domain_.?">[\s]*(.*?)[\s]*<\/li>/sg;
	
	push @bugdata,@examples;
    }
    else {
	push @bugdata, 0;
    }
    
    return \@bugdata;
}

#=====================================================================
# Slurp whole file, return data as single string.
#=====================================================================
sub slurpFile ($) {
    
    my $inFile = $_[0];
    
    local $/ = undef;
    
    local *INFILE;
    
    open (INFILE, "<${inFile}")
	or die "Couldn't open file ${inFile}: $!";
    
    my $infileText = <INFILE>;
    
    close (INFILE);
    
    return $infileText;
}

#=====================================================================
# Extract bugs from Ghostery bugs.js file.
#=====================================================================
sub getBugs ($$) {

    my $bugsDBFile = shift;
    my $verbose = shift;
   
    my $bugsdbtext = slurpFile($bugsDBFile);

    # As we're not looking for much from the json formatted file,
    # this will probably be good enough; otherwise, could use a real 
    # parser.
    my @bugsList = $bugsdbtext =~ m/name":"(.*?)"/g;
    
    @bugsList = getUnique(@bugsList);
    
    print "Found " . scalar(@bugsList) . " bugs.\n" if $verbose;
    
    return @bugsList;
}

#=====================================================================
# Converts the bug name to name suitable for Ghostery website, by 
# replacing spaces with underscores, and plus(+) with %2B.
#=====================================================================
sub bugToWeb ($) {
    
    my $input = shift;
    
    $input =~ s/\ /_/g ;
    $input =~ s/\+/\%2B/g;
    
    return $input;
}

#=====================================================================
# Converts the bug name to an appropriate filename, by converting 
# characters (e.g. space, /) to underscores.
#=====================================================================
sub bugToFile ($) {
    
    my $input = shift;
    
    $input =~ s/\ /_/g ;
    $input =~ s/\//_/g ;
    
    return $input;
}
#=====================================================================
# Cross-reference between examples found for the bugs and the list
# of top websites.
#=====================================================================
sub crossReference (\@\%\@){
    
    my @bugList = @{$_[0]};
    my %bugData = %{$_[1]};
    my @websites = @{$_[2]};
    
    my %newBugList = ();

    # Hash for the website list.
    my %tmpHash = ();
    $tmpHash{$_} = 1 foreach (@websites);
    
    foreach my $bug (@bugList) {
	
	my @tmpArray = @{$bugData{$bug}};
	
	my $ownerSite = shift(@tmpArray);
	my $occurrences = shift(@tmpArray);
	
	next unless $occurrences;
	
	# Find whether any of this bug's examples appears in list of top websites.
	my $bugMatched = 0;
	foreach my $example (@tmpArray) {
	    if ($tmpHash{$example}) {
		$bugMatched = 1;
	     	last;
	    }
	}
	
	if ($bugMatched) {
	    $newBugList{$bug} = [$ownerSite,$occurrences];
	}
    }
    
    return %newBugList;
}

#=====================================================================
# Print the bugs on appearing on the top sites.
#=====================================================================
sub printBugs ($@) {
    
    my $numberWebsites = shift;
    my %bugList = @_;
    
    local *FOUT;
    
    my $outFile = "bugs_in_top_${numberWebsites}_websites.txt";
    
    open(FOUT,">$outFile")
	or die "Couldn't open file ${outFile}";
    
    print FOUT "// List of bugs occurring on top ${numberWebsites} websites.\n";
    print FOUT "// Format: Name of bug -- Bug owner website -- Number of sites bug appears on.\n";
    
    # Create a simple array, so we can sort (descending order).
    my @flatArray = ();
    my $index = 0;
    foreach my $bug (keys %bugList) {
	my @tmpArray = @{$bugList{$bug}};
	$flatArray[$index++] = [$bug, $tmpArray[0],$tmpArray[1]];
    }
    @flatArray = sort {$b->[2] <=> $a->[2]} @flatArray;
    
    for(my $index = 0; $index < $#flatArray; $index++) {
	print FOUT $flatArray[$index][0] 
	    . " -- " 
	    . $flatArray[$index][1]
	    . " -- " .$flatArray[$index][2]
	    . "\n";
    }
    
    close(FOUT);
}

1;

#=====================================================================
