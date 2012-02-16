#!/usr/bin/perl
# Grant Bond
#This program will scan a given directory for music and extract the ID3 tags into an index.
#The index can then be modified and eventually written to a new path.
#The goal is to create a common structure for your music library
#The structure is Artist/Album/1Track.MP3

#TODO: Sanitize paths

use strict;
use warnings;
use File::Find;
use File::Copy;
use File::Path qw(make_path);
use Cwd;
use Image::ExifTool;
use Lingua::EN::Numbers qw(num2en num2en_ordinal);

my @list;
my %tags; #Each File is Here with a hash of ID3 tags
my $tags_ref = \%tags;
my %artists; #Final Hash o' Hashes.. %Artist -> %Album -> %TrackTitle {Values}
my $artist_ref = \%artists;
my $exifTool = new Image::ExifTool;
my @keep = qw(Year Track Album FileType AudioBitrate Artist Title AvgBitrate Albumartist Date);
my $oldSetting = $exifTool->Options(Duplicates => 0);
#Scans a directory for music files supported by ExifTool adding them to @list.
sub index {
	print "Please enter the source directory to index: ";
	my $sdir = <STDIN>; chomp($sdir);
	@list =();
	find sub {
		my $workingfile = getcwd() . "/" . $_;
		push(@list, $workingfile) if($_ =~ m/\.(wav|flac|m4a|wma|mp3|mp4|aac|ogg)+$/i);
	}, $sdir;
	&id3();
}
#Extracts ID3 tags from files in @list, adding ID3 tags to %tags.
sub id3 {
	my $total = scalar(@list);
	%tags = ();
	print "Retrieving ID3 tags.... this may take awhile!\n";
	print "This tool indexes all your music files.  It knows the Artist, Album, Year, Track, Track #, Bitrate, and File Type.\n";
	print "When searching the index simple enter a word or FLAC to get flac.  If you want to search a range of bit rates use the format \"> 160\" or \"< 128\"\n";
	print "Once you decide to write it will create Artist/Album/0Title.mp3 tree for each entry\n";
	my $i = 1;
	foreach (@list) {
		print "25% done\n" if $total / $i == 4;
		print "50% done\n" if $total / $i == 2;
		print "75% done\n" if $total / $i == (4/3);
		#SO SLOW! Is there a better way to do this?  Batch job..?
		$tags{"$_"} = $exifTool->ImageInfo("$_", @keep) or warn "*Error getting ID3 tags from $_\n";
		$i++;
	}
	&make_artists();
}
#Builds %artist -> %albums -> %songs -> attributes hash from %tags
sub make_artists {
	print "Building index...\n";
	%artists = ();
	for my $firstkey (sort keys %tags) {
		my $art = &sane($tags_ref->{$firstkey}->{"Albumartist"});
		my $alb = &cap($tags_ref->{$firstkey}->{"Album"});
		my $tit = &cap($tags_ref->{$firstkey}->{"Title"});
		my $fil = $tags_ref->{$firstkey}->{"FileType"};
		my $tra = $tags_ref->{$firstkey}->{"Track"};
		my $pat = $firstkey;
		my $bit = $tags_ref->{$firstkey}->{"AudioBitrate"};
		$art = &sane($tags_ref->{$firstkey}->{"Artist"}) if !defined($art);
		$art = &doors($art);
		if(defined($art) && defined($alb) && defined($tit) && defined($fil)) {
			$artists{$art} = &anon_hash() unless $artists{$art};
			$artists{$art}{$alb} = &anon_hash() unless $artists{$art}{$alb};
			if($artists{$art}{$alb}{$tit}) {
				my $i = 0;
				while($artists{$art}{$alb}{$tit}) {
					$i++;
					my $test = $tit . " d$i";
					if(!$artists{$art}{$alb}{$test}) {
						$tit = $test;
						next;
					}

				}
			}
			$artists{$art}{$alb}{$tit} = &anon_hash() unless $artists{$art}{$alb}{$tit};
			$artists{$art}{$alb}{$tit}{"filetype"} = $fil unless $artists{$art}{$alb}{$tit}{"filetype"};
			$artists{$art}{$alb}{$tit}{"path"} = $pat unless $artists{$art}{$alb}{$tit}{"path"};
			$artists{$art}{$alb}{$tit}{"track"} = &track($tra) unless $artists{$art}{$alb}{$tit}{"track"} || !defined($tra);
			if(defined($bit)) {
			$artists{$art}{$alb}{$tit}{"bitrate"} = &num($bit) unless $artists{$art}{$alb}{$tit}{"bitrate"};
			}
			else {
				$bit = $tags_ref->{$firstkey}->{"AvgBitrate"};
				$artists{$art}{$alb}{$tit}{"bitrate"} = &num($bit) unless $artists{$art}{$alb}{$tit}{"bitrate"} || !defined($bit);
			}
		}
		else {
			print "[Skipping] Error with tags in file: $pat\n";
			next;
		}
	}
}
sub anon_hash {
	my %temp;
	return \%temp;
}
sub anon_array {
	my @temp;
	return \@temp;
}
#Single digit tracks
sub track {
	my $text = shift;
	$text =~ s/\/.*//g;
	$text =~ s/^0//g;
	return $text;
}
#Replaces &, _, Numbers.
sub sane {
	my $text = shift;
	return $text if !defined($text);
	$text =~ s/&/and/g;
	$text =~ s/_/ /g;
	if($artists{$text}) {
		#$text =~ s/([\w']+)/\u\L$1/g;
		return &cap($text);
	}
	my $number = $text;
	if($number =~ m/\b\d\b/) {
		$number =~ s/\D//g;
		$number = num2en($number);
		$text =~ s/\b\d\b/$number/g;
	}
	#$text =~ s/([\w']+)/\u\L$1/g;
	return &cap($text);
}
#Captilize The First Letter
sub cap {
	my $text = shift;
	$text =~ s/([\w']+)/\u\L$1/g;
	return $text;
}
sub num {
	my $text = shift;
	$text =~ s/\D//g;
	return $text;
}
sub spaces {
	my $text = shift;
	$text =~ s/^\s+//;
	$text =~ s/\s+$//;
	return $text;
}
#The Doors -> Doors, The
sub doors {
	my $text = &spaces(shift);
	if ($text =~ m/^\bThe\b/i) {
		$text =~ s/^\bThe\s//i;
		$text = $text . ", The";
	}
	return $text;
}
#Build will create the file structure and then move the files
sub build {
	my $base = shift;
	for my $firstkey (keys %artists) {
		make_path("$base/$firstkey");
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			#Currently will break with "Through The Pain...";
			make_path("$base/$firstkey/$secondkey");
			for my $song (keys %{$artist_ref->{$firstkey}->{$secondkey}} ) {
				my $src = $artists{$firstkey}{$secondkey}{$song}{"path"};
				my $filetype = $artists{$firstkey}{$secondkey}{$song}{"filetype"};
				my $trackno = $artists{$firstkey}{$secondkey}{$song}{"track"};
				my $filename;
				if(defined($trackno)) {
					$filename = $trackno . $song . ".$filetype";
				}
				else {
					$filename = $song . ".$filetype";
				}
				move($src, "$base/$firstkey/$secondkey/$filename") or warn "*ERROR could not move file located at $src\n";
			}
		}
	}
}
##If there is a left over key with no values it removes it.
sub cleanartist {
	for my $firstkey (keys %artists) {
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			for my $thirdkey (keys %{$artist_ref->{$firstkey}->{$secondkey}} )
			{
				if(scalar(%{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}} ) ) {
				}
				else {
					delete $artist_ref->{$firstkey}->{$secondkey}->{$thirdkey} or warn "Could not remove indexes\n";
					print "\n$thirdkey is empty\n";
				}
			} ## end of $thirdkey
			if(scalar(%{$artist_ref->{$firstkey}->{$secondkey}} ) ) {
				#print scalar(%{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}} );
				#print "\n$thirdkey\n";
			}
			else {
				delete $artist_ref->{$firstkey}->{$secondkey} or warn "Could not remove indexes\n";
				print "\n$secondkey is empty\n";
			}
		} ##end of $secondkey
		if(scalar(%{$artist_ref->{$firstkey}} ) ) {
			#print scalar(%{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}} );
			#print "\n$thirdkey\n";
		}
		else {
			delete $artist_ref->{$firstkey} or warn "Could not remove indexes\n";
			print "\n$firstkey is empty\n";
		}
	} ##end of $firstkey
}
#Removes entries from index passed to it from &artistaction.
sub remove {
	my $removal_ref = shift;
	my %removal = %$removal_ref;
	for my $firstkey (keys %artists) {
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			for my $song (keys %{$artist_ref->{$firstkey}->{$secondkey}} ) {
				my $songs_path = $artist_ref->{$firstkey}->{$secondkey}->{$song}->{"path"};
				next if !defined($songs_path);
				if($removal{$songs_path}) {
					print "Removing from index $songs_path\n";
					delete $artist_ref->{$firstkey}->{$secondkey}->{$song} or warn "Could not remove indexes\n";
					my $testsong;
					my $i;
					if($song =~ m/d\d$/) {
						$i = substr($song, length($song)-1, length($song)-1)+1;
						$testsong = substr($song, 0, length($song)-1);
					}
					else {
						$i = 1;
						$testsong = $song . " d";
					}
					while($artist_ref->{$firstkey}->{$secondkey}->{"$testsong$i"}) {
						my $last = $testsong . ($i-1);
						if (($i - 1) == 0) {
							$artists{$firstkey}{$secondkey}{$song} = $artists{$firstkey}{$secondkey}{"$testsong$i"};
						$i++;
						}
						else {
							print "$last setting\n";
							my $ref = $artist_ref->{$firstkey}->{$secondkey}->{"$testsong$i"};
							$artists{$firstkey}{$secondkey}{$last} = $ref;
						$i++;
						}
					}
					$i--;
					delete $artists{$firstkey}{$secondkey}{"$testsong$i"};
				}
			}
		}
	}
	&cleanartist();
}
#High-level sub to interact with %artist can print / remove entries.
sub artistaction {
	my $action = &spaces(shift);
	my $match = shift;
	my $location = shift;
	my $operator = &spaces(shift);
	my $goal = &spaces(shift);
	if($action eq "p") {
		if($operator) {
			my @big = &print($location, $operator, $goal);
			print grep(/kbs/i, @big);
		}
		else {
			print grep(/$match/i, &print($location, 0, 0));
		}
	}
	
	if($action eq "r") {
		my %path_of_smalls;
		#Search for kbs range
		if($operator) {
			my @big = &print($location, $operator, $goal);
			my @small = grep(/kbs/i, @big);
			print "Removal of files based on kbs\n";
			for(my $i = 0; $i < scalar(@small); $i++) {
				print $i . ".) $small[$i]\n";
			}
			print "Type in numbers seprated by a space to keep or press enter if selection is what you want.\n";
			my $choice = <STDIN>; chomp($choice);
			my @selection = split(/\s+/, $choice);
			foreach (@selection) {
				delete $small[$_];
			}
			my @temparray;
			foreach(@small) {
				if(defined($_)) {
					push(@temparray, $_);
				}
			}
			@small = @temparray;
			print "\n\n\nThese files are currently selected for removal\n\n@small";
			print "Proceed with removal from index? [y/n]\n";
			$choice = <STDIN>; chomp($choice);
			#GTFO!
			next if $choice eq "n";
			%path_of_smalls = ();
			foreach(@small) {
				my $temppath = $_;
				if ($temppath =~ m/"(.+?)"/) {
	  			$temppath = $1;
				}
				$path_of_smalls{$temppath} = "1";
			}

		}
		else {
			my @big = &print($location, 0, 0);
			my @small = grep(/$match/i, @big);
			for(my $i = 0; $i < scalar(@small); $i++) {
				print $i . ".) $small[$i]\n";
			}
			print "Type in numbers seprated by a space to keep or press enter if selection is what you want.\n";
			my $choice = <STDIN>; chomp($choice);
			my @selection = split(/\s+/, $choice);
			foreach (@selection) {
				delete $small[$_];
			}
			my @temparray;
			foreach(@small) {
				if(defined($_)) {
					push(@temparray, $_);
				}
			}
			@small = @temparray;
			print "\n\n\nThese files are currently selected for removal\n\n@small";
			print "Proceed with removal from index? [y/n]\n";
			$choice = <STDIN>; chomp($choice);
			next if $choice eq "n";
			%path_of_smalls = ();
			foreach(@small) {
				my $temppath = $_;
				if ($temppath =~ m/"(.+?)"/) {
	  			$temppath = $1;
				}
				$path_of_smalls{$temppath} = "1";
			}
		}
		&remove(\%path_of_smalls);
	}
}
#Returns an array for greping/printing/removing
sub print {
	my $inc = shift;
	my $operator = shift;
	my $goal = shift;
	my @toprint = ();
	for my $firstkey (keys %artists) {
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			for my $thirdkey (keys %{$artist_ref->{$firstkey}->{$secondkey}}) {
				my @attributes;
				for my $forthkey (keys %{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}}) {
					my $value = $artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}->{$forthkey};
					if($forthkey eq "bitrate" && $operator) {
						if($operator eq ">") {
							push(@attributes, "$value kbs") if $value > $goal;
						}
						elsif($operator eq "<") {
							push(@attributes, "$value kbs") if $value < $goal;
						}
					}
					else {
						push(@attributes, "$value kbs") if $forthkey eq "bitrate";
					}
					push(@attributes, "$value") if $forthkey eq "filetype";
					
					push(@attributes, "\"$value\"") if $forthkey eq "path" && $inc;
				}
				push(@toprint, "$firstkey - $secondkey -> $thirdkey\n@attributes\n");
			}
		}
	}
	return @toprint;
}
#Menu for the user
sub menu {
	print "\n\nWhat would you like to do?\n";
	print "1) Print all music files matching x\n";
	print "2) Remove (from index) all music files matching x\n";
	print "3) Move & Rename indexed files\n";
	print "4) Enter a new source directory to index (or index again)\n";
	print "5) Quit!\n";
	print "Choice\> ";

	my $choice = <STDIN>; chomp($choice);
	while($choice !~ m/[1-6]/)
	{
		print "Choice\> ";
		$choice = <STDIN>; chomp $choice;
	}
	if ($choice eq "1") {
		print "You may enter an Arist, Album, Song, File Type, Bitrate (ie < 192 or > 128), or leave blank for all.\n";
		print "Select \> ";
		my $match = <STDIN>; chomp($match);
		if($match =~ m/[\<\>]/) {
			print "Include file path as well? [y/n]> ";
			my $schoice = <STDIN>; chomp($schoice);
			my $operator = $match;
			$operator =~ s/[^\<\>]*//g;
			my $goal = $match;
			$goal =~ s/\D//g;
			&artistaction("p", $match, 1, $operator, $goal) if $schoice eq "y";
			&artistaction("p", $match, 0, $operator, $goal) if $schoice eq "n";
		}
		else {
			print "Include file path as well? [y/n]> ";
			my $schoice = <STDIN>; chomp($schoice);
			&artistaction("p", $match, 1, 0, 0) if $schoice eq "y";
			&artistaction("p", $match, 0, 0, 0) if $schoice eq "n";	
		}
		
	}
	elsif ($choice eq "2") {
		print "You may enter an Arist, Album, Song, File Type, Bitrate, or leave blank for all.\n";
		print "Select \> ";
		my $match = <STDIN>; chomp($match);
		my $operator = $match;
		$operator =~ s/[^\<\>]*//g;
		my $goal = $match;
		$goal =~ s/\D//g;
		&artistaction("r", $match, 1, $operator, $goal);
	}
	elsif ($choice eq "3") {
		print "Include the path without the final \\"
		print "Enter directory to move indexed files to> ";
		my $dir = <STDIN>; chomp($dir);
		&build($dir);
	}
	&index() if $choice eq "4";
	exit if $choice eq "5";
	print Dumper($artist_ref) if $choice eq "6";
}

&index();
while(1) {
	&menu();
}