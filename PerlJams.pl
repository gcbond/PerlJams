#!/usr/bin/perl
# Grant Bond
#This program will scan a given directory for music and extract the ID3 tags into an index.
#The index can then be modified and eventually written to a new path.
#The goal is to create a common structure for your music library
#The structure is Artist/Album/1Track.MP3
#The files will be moved from the old source to the new directory.

use strict;
use warnings;
use File::Find;
use File::Copy;
use File::Path qw(make_path);
use Cwd;
use Image::ExifTool;
use Lingua::EN::Numbers qw(num2en num2en_ordinal);

my @list; #Array of Music Files
my %tags; #Each sane file is here with the hash of ID3 Tags.  File(Key) -> AnonHash {ID3(Key) -> Value}
my $tags_ref = \%tags;
my %artists; #Final Hash o' Hashes.. %Artist -> %Album -> %TrackTitle {Values}
my $artist_ref = \%artists;
my $exifTool = new Image::ExifTool;
my @keep = qw(Year Track Album FileType AudioBitrate Artist Title AvgBitrate Albumartist Date);
my $oldSetting = $exifTool->Options(Duplicates => 0); #Dismiss duplicate tags.
my $makecopies = 0;
#Scans a directory for music files supported by ExifTool adding them to @list.
sub index {
	print "Please enter the full path of the source directory to index> ";
	my $sdir = <STDIN>; chomp($sdir);
	@list =();
	#File::Find allows this to happen, it will go through each file including . and .. for a given directory.
	find sub {
		my $workingfile = getcwd() . "/" . $_;
		#Only add it to the list if it is music like.
		push(@list, $workingfile) if($_ =~ m/\.(wav|flac|m4a|wma|mp3|mp4|aac|ogg)+$/i);
	}, $sdir;
	&id3();  #Next step is to get all the ID3 tags.
}
#Extracts ID3 tags from files in @list, adding ID3 tags to %tags.
sub id3 {
	my $total = scalar(@list);
	%tags = ();  #Make sure %tags is empty first.
	print "Retrieving ID3 tags.... this may take awhile!\n";
	print "This tool indexes all your music files.  It knows the Artist, Album, Year, Track, Track #, Bitrate, and File Type.\n";
	print "When searching the index simple enter a word or FLAC to get flac.  If you want to search a range of bit rates use the format \"> 160\" or \"< 128\"\n";
	print "Once you decide to write it will create Artist/Album/0Title.mp3 tree for each entry, moving the old files from the source.\n";
	my $i = 1;
	foreach (@list) {
		print "25% done\n" if $total / $i == 4;
		print "50% done\n" if $total / $i == 2;
		print "75% done\n" if $total / $i == (4/3);
		#SO SLOW! Is there a better way to do this?  Batch job..?
		#$exifTool-ImageInfo() will return a hash of attributes(keys) with values.
		$tags{"$_"} = $exifTool->ImageInfo("$_", @keep) or warn "*Error getting ID3 tags from $_\n";
		$i++;
	}
	&make_artists();
}
#Builds %artist -> %albums -> %songs -> attributes hash from %tags
sub make_artists {
	print "Building index...\n";
	%artists = (); #Make sure %artists is empty first.
	#Okay now lets go through %tags and put it into %Artists.
	for my $firstkey (sort keys %tags) {
		#$firstkey is the full file path of the track.
		#3 Letter variables because they will not be used outside of this scope.
		####SUBS####
		# sane = Replaces & with 'and', _ ' ', 33 'thirty-three'.
		# cap = Captilize The First Letter Of Each Word.
		# track = Makes track numbers N instead of NN (ie 9 instead of 09 or 09/14).
		# doors = 'The Doors' becomes 'Doors, The'.
		# anon_hash = anonymous hash.
		# num = Returns the numbers in the string.
		############
		my $art = &sane($tags_ref->{$firstkey}->{"Albumartist"});
		my $alb = &cap($tags_ref->{$firstkey}->{"Album"});
		my $tit = &cap($tags_ref->{$firstkey}->{"Title"});
		my $fil = $tags_ref->{$firstkey}->{"FileType"};
		my $tra = &track($tags_ref->{$firstkey}->{"Track"});
		my $pat = $firstkey;
		my $bit = $tags_ref->{$firstkey}->{"AudioBitrate"};
		$art = &sane($tags_ref->{$firstkey}->{"Artist"}) if !defined($art); #Sometimes ID3 uses AlbumArtists or Artist
		$art = &doors($art);
		#Sometimes ID3 tags are not complete and leave stuff out so check to make sure we can atleast work with it first.
		#Otherwise just skip it because I currently have no way of easily finding out all the info.
		#If it is defined it is usually not blank ("") but just to make sure.
		if(defined($art) && defined($alb) && defined($tit) && defined($fil) || $art eq "" || $alb eq "" || $tit eq "" || $fil = "") {
			#Everything is there lets populate %artists now.
			#Don't overwrite [myArtist] if the hash already contains it.
			$artists{$art} = &anon_hash() unless $artists{$art};
			#Don't overwrite [myAlbum] if the hash already contains it.
			$artists{$art}{$alb} = &anon_hash() unless $artists{$art}{$alb};
			#If the hash already contains that title its a duplicate!
			#Handle duplicates by adding " d" + n to them.
			#This allows me later to easily go through checking for duplicates
			#Better than checking to see if title ends with a number which may be a legit song
			#and not me handeling duplicates.
			if($artists{$art}{$alb}{$tit}) {
				my $i = 0;

				while($artists{$art}{$alb}{$tit}) {
					$i++;
					#Test is the song + " d" + n. 
					my $test = $tit . " d$i";
					#As long as that duplicate already exists, keep going.
					if(!$artists{$art}{$alb}{$test}) {
						$tit = $test;
						next;
					}
				}
			}
			#Finally add the track title to the hash.
			$artists{$art}{$alb}{$tit} = &anon_hash() unless $artists{$art}{$alb}{$tit};
			#The next three really shouldn't need an unless because there shouldn't be a case where a
			#track has already been definied with attributes, but I'll keep it there.
			$artists{$art}{$alb}{$tit}{"filetype"} = $fil unless $artists{$art}{$alb}{$tit}{"filetype"};
			$artists{$art}{$alb}{$tit}{"path"} = $pat unless $artists{$art}{$alb}{$tit}{"path"};
			#Sometimes the track number is not defined, but thats OK.
			$artists{$art}{$alb}{$tit}{"track"} = $tra unless $artists{$art}{$alb}{$tit}{"track"} || !defined($tra);
			#Not all file types have a bit rate, FLAC does not have bitrate so as to not cause errors check first.
			if(defined($bit)) {
			$artists{$art}{$alb}{$tit}{"bitrate"} = &num($bit) unless $artists{$art}{$alb}{$tit}{"bitrate"};
			}
			else {
				#If bitrate isn't defined AvgBitrate should be as a last resort.
				#I have yet to see any files which /should/ have a bit rate but neither of these are defined.
				$bit = $tags_ref->{$firstkey}->{"AvgBitrate"};
				$artists{$art}{$alb}{$tit}{"bitrate"} = &num($bit) unless $artists{$art}{$alb}{$tit}{"bitrate"} || !defined($bit);
			}
		}
		#Tags didn't have enough info.  For now there is nothing I can do.
		else {
			print "[Skipping] Error with tags in file: $pat\n";
			next;
		}
	}
}
#Create an anonymous hash.
sub anon_hash {
	my %temp;
	return \%temp;
}
#Create an anonymous array.
sub anon_array {
	my @temp;
	return \@temp;
}
#Single digit tracks
sub track {
	my $text = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	return $text if !defined($text);
	$text =~ s/\/.*//g;
	$text =~ s/^0//g;
	return $text;
}
#Replaces &, _, Numbers.
sub sane {
	my $text = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	return $text if !defined($text);
	$text =~ s/&/and/g;
	$text =~ s/_/ /g;
	if($artists{$text}) {
		return &cap($text);
	}
	my $number = $text;
	if($number =~ m/\b\d\b/) {
		$number =~ s/\D//g;
		$number = num2en($number);
		$text =~ s/\b\d\b/$number/g;
	}
	return &cap($text);
}
#Captilize The First Letter
sub cap {
	my $text = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	$text =~ s/([\w']+)/\u\L$1/g if defined($text);
	return $text;
}
#Returns just the number
sub num {
	my $text = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	$text =~ s/\D//g if defined($text);
	return $text;
}
#Get rid of spaces before and after.
sub spaces {
	my $text = shift;
	return $text if !defined($text);
	$text =~ s/^\s+//;
	$text =~ s/\s+$//;
	return $text;
}
#The Doors -> Doors, The
sub doors {
	my $text = &spaces(shift);
	return $text if !defined($text);
	if ($text =~ m/^\bThe\b/i) {
		$text =~ s/^\bThe\s//i;
		$text = $text . ", The";
	}
	return $text;
}
#Build will create the file structure and then move the files
sub build {
	#sanitized gets rid of illegal characters
	my $base = &sanitize(shift, 1);
	print "Files will be located in $base\n";
	print "Program will ask to overwrite in case of conflict.\n";
	# $firstkey is the artist
	# $secondkey is the album
	# $song is the song
	for my $firstkey (keys %artists) {
		my $level1 = &sanitize($firstkey);
		#Make the directory for the artist.
		make_path("$base/$level1");
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			my $level2 = &sanitize($secondkey);
			#Make the directory for the album.
			make_path("$base/$level1/$level2");
			for my $song (keys %{$artist_ref->{$firstkey}->{$secondkey}} ) {
				my $level3 = &sanitize($song);
				my $src = $artists{$firstkey}{$secondkey}{$song}{"path"};
				my $filetype = $artists{$firstkey}{$secondkey}{$song}{"filetype"};
				my $trackno = $artists{$firstkey}{$secondkey}{$song}{"track"};
				my $filename;
				#Is there a track number? If so we can do 2Title.mp3 else Title.mp3
				if(defined($trackno)) {
					$filename = $trackno . $level3 . ".$filetype";
				}
				else {
					$filename = $level3. ".$filetype";
				}
				#This is the ulimate resting place for the song
				my $musicfile = "$base/$level1/$level2/$filename";
				#Incase there is a file there, don't want to overwrite it
				#This could use work right now it only allows you to overwrite or skip.
				if(-e $musicfile) {
					print "$musicfile already exists! Overwrite?[y/n by default]> ";
					my $choice = <STDIN>; chomp($choice);
					if($choice eq "y") {
						#$makecopies is true if you opted to copy instead of move.
						if($makecopies) {
							copy($src, "$base/$level1/$level2/$filename") or warn "*ERROR could not move file located at $src\n";
						}
						else {
							move($src, "$base/$level1/$level2/$filename") or warn "*ERROR could not move file located at $src\n";
						}
					}
				}
				else {
					if($makecopies) {
						copy($src, "$base/$level1/$level2/$filename") or warn "*ERROR could not move file located at $src\n";
					}
					else {
						move($src, "$base/$level1/$level2/$filename") or warn "*ERROR could not move file located at $src\n";
					}
					
				}
			}
		}
	}
	print "Done creating and populating directories!\n";
	#Done building, do you want to do another run?
	&postbuild();
}
#Get rid of illegal chars, forcefully.
#In otherwords don't check with the user after removing illegal chars.
sub sanitize {
	my $text = shift;
	if(shift) {
		$text =~ s/[\<|\>|\.|\?|\||\*|\"]//g if defined($text);
	}
	else {
		$text =~ s/[\<|\>|\.|\?|\||\:|\*|\"|\\|\/]//g if defined($text);
	}
	return $text;
}
##If there is a left over key with no values it removes it.
##Had an occurance where it left behind a single entry (of a duplicate song).
sub cleanartist {
	for my $firstkey (keys %artists) {
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			for my $thirdkey (keys %{$artist_ref->{$firstkey}->{$secondkey}} ) {	
				#The scalar context will be not 0 if there is something there.
				delete $artist_ref->{$firstkey}->{$secondkey}->{$thirdkey} or warn "Could not remove indexes\n" unless scalar(%{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}} );
			} ## end of $thirdkey
			delete $artist_ref->{$firstkey}->{$secondkey} or warn "Could not remove indexes\n" unless scalar(%{$artist_ref->{$firstkey}->{$secondkey}} );
		} ##end of $secondkey
		delete $artist_ref->{$firstkey} or warn "Could not remove indexes\n" unless scalar(%{$artist_ref->{$firstkey}} );
	} ##end of $firstkey
}
#Removes entries from index passed to it from &artistaction.
sub remove {
	my $removal_ref = shift;
	#Hash of file paths to remove, the only unique way of easily checking.
	my %removal = %$removal_ref;
	#Going to have to go through everything unless I tell it where to look, currently I do not.
	for my $firstkey (keys %artists) {
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			for my $song (keys %{$artist_ref->{$firstkey}->{$secondkey}} ) {
				my $songs_path = $artist_ref->{$firstkey}->{$secondkey}->{$song}->{"path"};
				#Not sure why path would not be defined.
				next if !defined($songs_path);
				#If the song path we are currently add is in the list for removal lets delete it from %artists
				if($removal{$songs_path}) {
					print "Removing from index $songs_path\n";
					delete $artist_ref->{$firstkey}->{$secondkey}->{$song} or warn "Could not remove indexes\n";
					#If there is duplicates, decrement them
					my $testsong;
					my $i;
					#Add a d1 if song does not have it.
					if($song =~ m/d\d$/) {
						$i = substr($song, length($song)-1, length($song)-1)+1;
						$testsong = substr($song, 0, length($song)-1);
					}
					else {
						$i = 1;
						$testsong = $song . " d";
					}
					#While %artists has the duplicate
					#$testsong is already appended with the " d"
					while($artist_ref->{$firstkey}->{$secondkey}->{"$testsong$i"}) {
						#the last song i checked before this one
						my $last = $testsong . ($i-1);
						if (($i - 1) == 0) {
							#bump down to just the title if thats what we deleted previously.
							$artists{$firstkey}{$secondkey}{$song} = $artists{$firstkey}{$secondkey}{"$testsong$i"};
						$i++;
						}
						else {
							#Make what we just passed the value of the current thing were on (This is decrementing)
							my $ref = $artist_ref->{$firstkey}->{$secondkey}->{"$testsong$i"};
							$artists{$firstkey}{$secondkey}{$last} = $ref;
						$i++;
						}
					}
					$i--;
					#Finally if this is the end of the line, we already decremented so delete this
					#Right now it just makes the song have no values(no path, no filetype, nothing), can't figure out how to delete the 
					#actual song from the album hash without deleting all the songs in that album.
					delete $artists{$firstkey}{$secondkey}{"$testsong$i"};
				}
			}
		}
	}
	#After were done removing, lets go ahead and remove those empty hashes.
	&cleanartist();
}
#High-level sub to interact with %artist can print / remove entries.
sub artistaction {
	#$action is either p to print or r to remove
	my $action = &spaces(shift);
	#$match is for greping
	my $match = shift;
	#$locatin is true to include location
	my $location = shift;
	#$operator for doing  > or < searches of bitrate
	my $operator = &spaces(shift);
	#$goal for doing > or < searches, this is the bitrate goal to achieve.
	my $goal = &spaces(shift);
	if($action eq "p") {
		if($operator) {
			#@big is list of all the files.
			my @big = &print($location, $operator, $goal);
			#greping for kbs because doing a bitrate range search
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
			#@big is list of all the files
			my @big = &print($location, $operator, $goal);
			#@small is all the files that have a defined kbs
			my @small = grep(/kbs/i, @big);
			print "Removal of files based on kbs\n";
			for(my $i = 0; $i < scalar(@small); $i++) {
				print $i . ".) $small[$i]\n";
			}
			#Allow them to NOT remove entries from the index.
			print "Type in numbers seprated by a space to keep or press enter if selection is what you want> ";
			my $choice = <STDIN>; chomp($choice);
			my @selection = split(/\s+/, $choice);
			foreach (@selection) {
				#They chose to keep stuff so remove it from the @small
				delete $small[$_];
			}
			my @temparray;
			foreach(@small) {
				#If they previously deleted something it will leave a null value.
				if(defined($_)) {
					push(@temparray, $_);
				}
			}
			@small = @temparray;
			#Last chance to get out.
			print "\n\n\nThese files are currently selected for removal\n\n@small";
			$choice = "";
			while ($choice !~ m/[y|n]/) {
				print "Proceed with removal from index? [y/n]> ";
				$choice = <STDIN>; chomp($choice);
			}
			if($choice eq "y") {
				%path_of_smalls = ();
				foreach(@small) {
					my $temppath = $_;
					if ($temppath =~ m/"(.+?)"/) {
		  			$temppath = $1;
					}
					$path_of_smalls{$temppath} = "1";
				}
			}
		}
		#This is for non-range searches, so normal greping.
		else {
			my @big = &print($location, 0, 0);
			my @small = grep(/$match/i, @big);
			for(my $i = 0; $i < scalar(@small); $i++) {
				print $i . ".) $small[$i]\n";
			}
			print "Type in numbers seprated by a space to keep or press enter if selection is what you want> ";
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
			$choice = "";
			while ($choice !~ m/[y|n]/) {
				print "Proceed with removal from index? [y/n]> ";
				$choice = <STDIN>; chomp($choice);
			}
			if($choice eq "y") {
				%path_of_smalls = ();
				foreach(@small) {
					my $temppath = $_;
					if ($temppath =~ m/"(.+?)"/) {
		  			$temppath = $1;
					}
					$path_of_smalls{$temppath} = "1";
				}
			}
		}
		&remove(\%path_of_smalls);
	}
}
#Returns an array for greping/printing/removing
#Basically makes the hash readable and interactable.
sub print {
	#$inc = True? Then include filenames
	my $inc = shift;
	#$operator = True? then doing a range search < or >
	my $operator = shift;
	#$goal is defined with a value if $operator is defined
	my $goal = shift;
	my @toprint = ();
	#Artist level
	for my $firstkey (keys %artists) {
		#Album level
		for my $secondkey (keys %{$artist_ref->{$firstkey}} ) {
			#Song level
			for my $thirdkey (keys %{$artist_ref->{$firstkey}->{$secondkey}}) {
				my @attributes;
				#Song Attributes level
				for my $forthkey (keys %{$artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}}) {
					#value of the attribute
					my $value = $artist_ref->{$firstkey}->{$secondkey}->{$thirdkey}->{$forthkey};
					if($forthkey eq "bitrate" && $operator) {
						#If its a bitrate and were doing a range search then only add song if its good
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
	print "3) Copy/Move & Rename indexed files\n";
	print "4) Enter a new source directory to index (or index again)\n";
	print "5) Quit!\n";
	print "Choice\> ";

	my $choice = <STDIN>; chomp($choice);
	while($choice !~ m/[1-5]/)
	{
		print "Choice\> ";
		$choice = <STDIN>; chomp $choice;
	}
	&preprint if $choice eq "1";
	&preremove() if $choice eq "2";
	&prebuild() if $choice eq "3";
	&index() if $choice eq "4";
	exit if $choice eq "5";
}
#Print Menu
sub preprint{
	print "You may enter an Artist, Album, Song, File Type, Bitrate (ie < 192 or > 128), or leave blank for all.\n";
	print "Select \> ";
	my $match = <STDIN>; chomp($match);
	#if the match has a < or > we must be doing a range search
	if($match =~ m/[\<\>]/) {
		my $schoice = "";
		while($schoice !~ m/[y|n|q]/) {
			print "Include file path as well? [y/n/q to quit]> ";
			$schoice = <STDIN>; chomp($schoice);
		}
		my $operator = $match;
		$operator =~ s/[^\<\>]*//g;
		my $goal = $match;
		$goal =~ s/\D//g;
		#artistaction is called with action [p|r], string to match, [<|>], target_kbs
		&artistaction("p", $match, 1, $operator, $goal) if $schoice eq "y";
		&artistaction("p", $match, 0, $operator, $goal) if $schoice eq "n";
	}
	else {
		my $schoice = "";
		while($schoice !~ m/[y|n|q]/) {
			print "Include file path as well? [y/n/q to quit]> ";
			$schoice = <STDIN>; chomp($schoice);
		}
		#artistaction is called with action [p|r], string to match, [<|>], target_kbs
		#in this case no range search so the last two should be false.
		&artistaction("p", $match, 1, 0, 0) if $schoice eq "y";
		&artistaction("p", $match, 0, 0, 0) if $schoice eq "n";	
	}
}
#Remove menue
sub preremove {
	print "You may enter an Artist, Album, Song, File Type, Bitrate (ie < 192 or > 128), or leave blank for all.\n";
	print "Select [q to quit]\> ";
	#Must include file paths because thats how I ultimately remove from %artist index.
	my $match = <STDIN>; chomp($match);
	my $operator = $match;
	$operator =~ s/[^\<\>]*//g;
	my $goal = $match;
	$goal =~ s/\D//g;
	&artistaction("r", $match, 1, $operator, $goal) unless $match eq "q";
}
#Build Menu
sub prebuild {
	#Option to copy instead of move
	print "Copy old files instead of moving them? [y/n by default]> ";
	my $choice = <STDIN>; chomp($choice);
	$makecopies = 1 if $choice eq "y";
	print "Enter directory to move/copy indexed files to [q to quit]> ";
	my $dir = <STDIN>; chomp($dir);
	#Remove \ or / at the end because that breaks stuff.
	$dir =~ s/[\\|\/]$//;
	&build($dir) unless $dir eq "q";
}
#After build Menu
sub postbuild {
	$makecopies = 0;
	my $choice = "";
 	while($choice !~ m/[y|n]/) {
 		print "\n\nRun again? [y/n]> ";
 		$choice = <STDIN>; chomp($choice);
 	}
 	&index() if $choice eq "y";
 	exit if $choice eq "n";
}
#No point in showing the menu without having an index first
&index();
#Always at the menu unless doing something else.
while(1) {
	&menu();
}