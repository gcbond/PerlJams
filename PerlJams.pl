#!/usr/bin/perl
# Author: Grant Bond (gcb4703 [at] rit.edu)
# Co-Author: Charles Lundblad
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# This program will index a given directory for music files and extract the ID3 tags 
# into an index that you can then sort and parse though.
# The index can then be modified and eventually written to a new path.
# The goal is to create a common structure for your music library
# The structure is EX: Artist/Album/1 - Track.mp3
# The files will be moved/copied from the old source to the new directory.
# Check error.log for details on why files were not indexed.

use strict;
use warnings;
use File::Find;
use File::Copy;
use File::Path qw(make_path);
use Cwd;
use Image::ExifTool;
use Lingua::EN::Numbers qw(num2en num2en_ordinal);
use Storable;
use Term::ANSIColor;

my @rawlist; #Array of raw music files.
my %tags; #Each sane file is here with the hash of ID3 Tags.  File(Key) -> AnonHash {ID3(Key) -> Value}
my $tags_ref = \%tags;
my %artists; #Final Hash o' Hashes.. %Artist -> %Album -> %TrackTitle {Values}
my $artist_ref = \%artists;
my $exifTool = new Image::ExifTool; #For more info check out http://www.sno.phy.queensu.ca/~phil/exiftool/
my @keep = qw(FileSize Year Track Album FileType AudioBitrate Artist Title AvgBitrate Albumartist Date);
my $oldSetting = $exifTool->Options(Duplicates => 0); #Dismiss duplicate tags.
my $error_log_path = getcwd() . "/error.log";
my $saved_index_path = getcwd() . "/index.pl";
my $artist_size = 0;
my $verbose = 0;
my $operating_system = $^O;
my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @weekDays = qw(Sun Mon Tue Wed Thu Fri Sat Sun);
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;
my $theTime = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";
&printerror("######################################\n$theTime\n");

if(defined($ARGV[0]) && $ARGV[0] =~ /^--verbose$/ ){
	$verbose = 1;
}
print "Welcome to PerlJams.  This is a utility designed to organize your music into directories by Artist\\Album\\Track.mp3.\n";
print "First the program needs to scan your music by selecting option 1.\n";
print "Afterwards you can search and remove items from the index created by PerlJams.  Once your happy you can then move or copy to a new directory\n";
print "You may save the index to come back to at a later time.  Index is saved as index.pl\n";
print "You can generate a sql script to create a database to publish on your website if you wish. (Check the web folder for more info.)\n";
print "If duplicate files are found, the better quality one is kept.\n";
print "Check error.log for issues with music files.\n";
print "--------------------------------------------\n\n";

#&index();
while(1) {
	&menu();
}
#Menu for the user
sub menu {
	print "What would you like to do?\n";
	print "1) Enter a new source directory to index (or index again)\n";
	print "2) Print all music files matching x\n";
	print "3) Remove (from index) all music files matching x\n";
	print "4) Save index\n";
	print "5) Read saved index\n";
	print "6) Move/Copy indexed files\n";
	print "7) Create SQL script\n";
	print "8) Quit!\n";
	print "Choice\> ";

	my $choice = <STDIN>; chomp($choice);
	while($choice !~ m/[1-8]/)
	{
		print "Choice> ";
		$choice = <STDIN>; chomp $choice;
	}
	&index() if $choice eq "1";
	&preprint if $choice eq "2";
	&preremove() if $choice eq "3";
	&serializeindex() if $choice eq "4";
	&unserializeindex() if $choice eq "5";
	&prebuild() if $choice eq "6";
	&presql() if $choice eq "7";
	exit if $choice eq "8";
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
#Print errors to a log instead of cluttering the screen as much.
sub printerror {
	#print "error printing\n";
	my $text = shift;
	open(ERRORLOG, ">> $error_log_path") or warn "Could not open error log to write\n";
	print ERRORLOG "$text";
	close(ERRORLOG);
}
sub serializeindex {
	print "Saving index to $saved_index_path\n";
	store $artist_ref, "$saved_index_path";
}
sub unserializeindex {
	print "Retrieving index from $saved_index_path\n";
	$artist_ref = retrieve("$saved_index_path") or warn "File does not exist or cannot be read!\n";
	%artists = %{$artist_ref};
}
#Scans a directory for music files supported by ExifTool adding them to @rawlist.
sub index {
	my @sdirs;
	my $choice = "t";
	print "Please enter the full path of the source directory to index [enter q when finished]";
	while($choice ne "q") {
		print "> ";
		$choice = <STDIN>; chomp($choice);
		push(@sdirs, $choice) unless $choice eq "q";
	}
	@rawlist =();
	#File::Find allows this to happen, it will go through each file including the files . and .. for a given directory.
	foreach my $sdir(@sdirs) {
		find sub {
			my $workingfile = getcwd() . "/" . $_;
			if ($workingfile =~ /\.skip/i) {
				print "BECAUSE YOU TOLD ME TO $workingfile\n";
				return;
			}
			#Only add it to the list if it is music like.
			push(@rawlist, $workingfile) if($_ =~ m/\.(wav|flac|m4a|wma|mp3|mp4|aac|ogg)+$/i);
		}, $sdir;
	}
	&id3();  #Next step is to get all the ID3 tags.
}
#Extracts ID3 tags from files in @rawlist, adding ID3 tags to %tags.
sub id3 {
	($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
	$year = 1900 + $yearOffset;
	$theTime = "$hour:$minute:$second, $weekDays[$dayOfWeek] $months[$month] $dayOfMonth, $year";
	print "Prcoess started at $theTime.\n";
	my $music_list_length = scalar(@rawlist);
	%tags = ();  #Make sure %tags is empty first.
	print "Retrieving ID3 tags.... this may take awhile!\n";
	my $i = 1;
	foreach (@rawlist) {
		print "25% done\n" if $music_list_length / $i == 4;
		print "50% done\n" if $music_list_length / $i == 2;
		print "75% done\n" if $music_list_length / $i == (4/3);
		if($verbose){
			print "(" . $i . " of " . $music_list_length . ") Retrieving ID3 tags from: $_\n";
		}
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
	my $no_id3_tags = 0;
	my $files_with_lower_bitrate = 0;
	my $dupes = 0;
	$artist_size = 0;
	#Okay now lets go through %tags and put it into %Artists.
	for my $filepath (sort keys %tags) {
		#$filepath is the full file path of the track.
		#3 Letter variables because they will not be used outside of this scope.
		####SUBS####
		# sane = Replaces & with 'and', _ ' ', 33 'thirty-three'.
		# cap = Captilize The First Letter Of Each Word.
		# track = Makes track numbers N instead of NN (ie 9 instead of 09 or 09/14).
		# doors = 'The Doors' becomes 'Doors, The'.
		# anon_hash = anonymous hash.
		# num = Returns the numbers in the string.
		############
		my $artist = &sane($tags_ref->{$filepath}->{"Albumartist"}, 1);
		my $album = &sane($tags_ref->{$filepath}->{"Album"}, 1);
		my $title = &sane($tags_ref->{$filepath}->{"Title"});
		my $file_type = &type($tags_ref->{$filepath}->{"FileType"});
		my $file_size = $tags_ref->{$filepath}->{"FileSize"};
		my $track = $tags_ref->{$filepath}->{"Track"};
		my $audio_bitrate = $tags_ref->{$filepath}->{"AudioBitrate"};
		my $current_hash_bitrate = 0;
		$artist_size += &num($file_size) if defined($file_size);
		$artist = &sane($tags_ref->{$filepath}->{"Artist"}, 1) if !defined($artist); #Sometimes ID3 uses AlbumArtists or Artist
		$artist = &doors($artist);
		#Sometimes ID3 tags are not complete and leave stuff out so check to make sure we can atleast work with it first.
		#Otherwise just skip it because I currently have no way of easily finding out all the info.
		#If it is defined it is usually not blank ("") but just to make sure.
		if(defined($artist) && defined($album) && defined($title) && defined($file_type)) {
			if($file_type !~ m/(wav|flac|m4a|wma|mp3|mp4|aac|ogg)/i) {
				&printerror("Error with tags in file $filepath\n\tError with filetype\n");
				$no_id3_tags++;
				if($verbose) {
					print color 'Bold Red' if $operating_system =~ m/(linux|darwin)/i;
					print "[Skipping] Error with tags in file: $filepath\n";
					print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
				}
				next;
			}
			if($artist eq "" || $album eq "" || $title eq "" || $file_type eq "") {
				&printerror("Error with tags in file $filepath\n");
				&printerror("\tError with Artist\n") if $artist eq "";
				&printerror("\tError with Album\n") if $album eq "";
				&printerror("\tError with Title\n") if $title eq "";
				$no_id3_tags++;
				if($verbose) {
					print color 'Bold Red' if $operating_system =~ m/(linux|darwin)/i;
					print "[Skipping] Error with tags in file: $filepath\n";
					print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
				}
				next;
			}
			#Everything is there lets populate %artists now.
			#Don't overwrite [myArtist] if the hash already contains it.
			$artists{$artist} = &anon_hash() unless $artists{$artist};
			#Don't overwrite [myAlbum] if the hash already contains it.
			$artists{$artist}{$album} = &anon_hash() unless $artists{$artist}{$album};
			$artists{$artist}{$album}{$title} = &anon_hash() unless $artists{$artist}{$album}{$title};
			#Checking for dupes
			if($artists{$artist}{$album}{$title}{"filetype"}) {
				#count duplcate files
				$dupes++;
				#only update hash is new file has higher bitrate
				if(defined($audio_bitrate) && defined($artists{$artist}{$album}{$title}{"bitrate"})) {
					my $current_hash_bitrate = $artists{$artist}{$album}{$title}{"bitrate"};
					if(&num($audio_bitrate) > $current_hash_bitrate){
						#Increment files with lower bitrate
						$files_with_lower_bitrate++;
						#change the filepath in this hash to the higher quality version
						$artists{$artist}{$album}{$title}{"path"} = $filepath
					}
				}
			}
			#The next three really shouldn't need an unless because there shouldn't be a case where a
			#track has already been definied with attributes, but I'll keep it there.
			$artists{$artist}{$album}{$title}{"filetype"} = lc($file_type) unless $artists{$artist}{$album}{$title}{"filetype"};
			$artists{$artist}{$album}{$title}{"path"} = $filepath unless $artists{$artist}{$album}{$title}{"path"};
			$artists{$artist}{$album}{$title}{"size"} = $file_size unless $artists{$artist}{$album}{$title}{"size"};
			#Sometimes the track number is not defined, but thats OK.
			$artists{$artist}{$album}{$title}{"track"} = &track($track) unless $artists{$artist}{$album}{$title}{"track"} || !defined($track);
			#Not all file types have a bit rate, FLAC does not have bitrate so as to not cause errors check first.
			if(defined($audio_bitrate)) {
				$artists{$artist}{$album}{$title}{"bitrate"} = &num($audio_bitrate) unless $artists{$artist}{$album}{$title}{"bitrate"};
			}
			else {
				#If bitrate isn't defined AvgBitrate should be as a last resort.
				#I have yet to see any files which /should/ have a bit rate but neither of these are defined.
				$audio_bitrate = $tags_ref->{$filepath}->{"AvgBitrate"};
				$artists{$artist}{$album}{$title}{"bitrate"} = &num($audio_bitrate) unless $artists{$artist}{$album}{$title}{"bitrate"} || !defined($audio_bitrate);
			}
		}
		#Tags didn't have enough info.  For now there is nothing I can do.
		else {
			$no_id3_tags++;
			if($verbose) {
				print color 'Bold Red' if $operating_system =~ m/(linux|darwin)/i;
				print "[Skipping] Error with tags in file: $filepath\n";
				print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
			}
			&printerror("Error with tags in file $filepath\n");
			&printerror("\tError with Artist\n") if !defined($artist);
			&printerror("\tError with Album\n") if !defined($album);
			&printerror("\tError with Title\n") if !defined($title);
			next;
		}
	}
	#%tags is now useless and just taking up space, empty it.
	%tags = ();
	print "\nTotal files checked: " . scalar(@rawlist) . "\n";
	print color 'Bold Red' if $operating_system =~ m/(linux|darwin)/i;
	print "Files with Bad/No ID3 Tags: " . $no_id3_tags . "\n";
	print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
	print "Files dropped because a better quality version was found: " . $files_with_lower_bitrate . "\n";
	print "Duplicate files not counted: " . $dupes . "\n";
	#print "Total Size is = $artist_size MB\n";
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
#Removes 'audio' from audio/mp3 in filetypes.
sub type {
	my $text = shift;
	return $text if !defined($text);
	$text =~ s/audio\///;
	return $text;
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
#Replaces &, _, Numbers.
sub sane {
	my $text = shift;
	my $checkNumber = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	return $text if !defined($text);
	$text =~ s/&/and/g;
	$text =~ s/_/ /g;
	return &cap($text) unless $checkNumber;
	my $number = $text;
	if($number =~ m/\s\d\s/) {
		$number =~ s/\D//g;
		$number = num2en($number);
		$text =~ s/\s\d\s/$number/g;
	}
	return &cap($text);
}

#Captilize The First Letter Of Each Word
sub cap {
	my $text = shift;
	return $text if !defined($text) || $text eq "";
	#Replace wierd characters
	$text =~ s/(à|á|â|ã|ä|å|À|Á|Â|Ã|Å)/a/g;
	$text =~ s/(ç|Ç)/c/g;
	$text =~ s/(è|é|ê|ë|È|É|Ê|Ë)/e/g;
	$text =~ s/(ì|í|î|ï|Ì|Í|Î|Ï)/i/g;
	$text =~ s/(ð|Ð)/d/g;
	$text =~ s/(ñ|Ñ)/n/g;
	$text =~ s/(ò|ó|ô|õ|ö|ø|Ò|Ó|Ô|Õ|Ö|Ø)/o/g;
	$text =~ s/(ù|ú|û|ü|Ù|Ú|Û|Ü)/u/g;
	$text =~ s/(ý|ÿ|Ý|Ÿ)/y/g;
	$text =~ s/(š|Š|\$)/s/g;
	$text =~ s/(¥)/y/g;
	#These bare words are not allowed in Windows.
	$text =~ s/\b(com1|com2|com3|com4|com5|com6|com7|com8|com9|lpt1|lpt2|lpt|lpt3|lp4|lpt5|lpt6|lpt7|lpt8|lpt9|con|nul|pm)\b//g;
	$text =~ s/([\w']+)/\u\L$1/g;
	#Get rid of any other junk
	$text =~ s/[^A-Za-z0-9\s\-\[\]\(\)_\|!|')]//g;
	return &spaces($text);
}

#Returns just the number
sub num {
	my $text = shift;
	#Since I call this right after trying to initilize it, make sure its not null.
	$text =~ s/[^\d.]//g if defined($text);
	return $text;
}

#Get rid of spaces before and after.
sub spaces {
	my $text = shift;
	return $text if !defined($text);
	$text =~ s/\s{2,}/ /g;
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

#Build Menu
sub prebuild {
	print "Enter directory to move/copy indexed files to [q to quit]> ";
	my $dir = <STDIN>; chomp($dir);
	#Remove \ or / at the end because that breaks stuff.
	$dir =~ s/[\\|\/]$//;
	&build($dir) unless $dir eq "q";
}

#Build will create the file structure and then move the files
sub build {
	#sanitized gets rid of illegal characters
	my $base = &sanitize(shift, 1);
	print "Files will be located in $base\n";
	my $moveFile;
	my $choice;
	$choice = 0;
	$moveFile = 0;

	print "Moving files to $base\n";
	print "Would you like to copy or move your source files?\n";
	print "1) Copy\n";
	print "2) Move\n";
	print "Choice: ";
	
	$choice = <STDIN>; chomp($choice);
	while($choice !~ m/[1-2]/) {
		print "Choice: ";
		$choice = <STDIN>; chomp $choice;
	}
	if($choice == 1) {
		$moveFile = 0;
	}
	if($choice == 2) {
		$moveFile = 1;
	}

	$choice = 0;
	print "\n\nMoving files to $base\n";
	print "Please make one last decision and I won't bother you anymore, please pick one.\n";
	print "1) Overwrite existing files, if any, assume new file is better\n";
	print "2) Overwrite existing file ONLY if source file is a higher bitrate\n";
	print "3) Do not overwrite existing files, only add\n";
	print "Choice: ";
	
	$choice = <STDIN>; chomp($choice);
	while($choice !~ m/[1-3]/) {
		print "Choice: ";
		$choice = <STDIN>; chomp $choice;
	}
	# $artistName is the artist
	# $albumName is the album
	# $song is the song
	for my $artistName (keys %artists) {
		my $artistDirectory = &sanitize($artistName);
		#Make the directory for the artist.
		make_path("$base/$artistDirectory");
		for my $albumName (keys %{$artist_ref->{$artistName}} ) {
			my $albumDirectory = &sanitize($albumName);
			#Make the directory for the album.
			make_path("$base/$artistDirectory/$albumDirectory");
			for my $song (keys %{$artist_ref->{$artistName}->{$albumName}} ) {
				my $trackTitle = &sanitize($song);
				my $sourceFileLocation = $artists{$artistName}{$albumName}{$song}{"path"};
				my $file_type = $artists{$artistName}{$albumName}{$song}{"filetype"};
				my $trackno = $artists{$artistName}{$albumName}{$song}{"track"};
				my $new_file_bitrate = $artists{$artistName}{$albumName}{$song}{"bitrate"};
				my $titleFormat;
				if(defined($trackno)) {
					$titleFormat = $trackno . " - " . $trackTitle . ".$file_type";
				}
				else {
					$titleFormat = $trackTitle. "." . lc($file_type);
				}
				my $musicFilePath = "$base/$artistDirectory/$albumDirectory/$titleFormat";
								
				if(-e $musicFilePath) {
					if($choice == 1) {
						if($moveFile == 0) {
							if($verbose){
								print "Copying $sourceFileLocation --> $musicFilePath\n";
							}		
							copy($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not copy file located at $sourceFileLocation\n" && &printerror("Error copying $sourceFileLocation -> $musicFilePath\n");
						}
						else {
							if($verbose){
								print "Moving $sourceFileLocation --> $musicFilePath\n";
							}
							move($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not move file located at $sourceFileLocation\n" && &printerror("Error moving $sourceFileLocation -> $musicFilePath\n");
						}
					}
					if($choice == 2){
						my $tag = $exifTool->ImageInfo($musicFilePath, @keep) or warn "*Error getting ID3 tags from $musicFilePath\n" && &printerror("BAD ID3 Tags $musicFilePath\n");
						my $AvgBitrate = &num($tag->{"AvgBitrate"});
						my $AudioBitrate = &num($tag->{"AudioBitrate"});
						my $bitrate;

						if(defined($AvgBitrate)){
							$bitrate = $AvgBitrate;
						}	
						if(defined($AudioBitrate)){
							$bitrate = $AudioBitrate;
						}	
						if(defined($bitrate) && $new_file_bitrate){
							if($new_file_bitrate > $bitrate){
								if($verbose){
									print color 'Bold Green' if $operating_system =~ m/(linux|darwin)/i;
									print "New file bitrate of " . $new_file_bitrate . " is > than " . $bitrate . " Replacing\n";
									print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
								}
								if($moveFile == 0) {
									if($verbose){
										print "Copying $sourceFileLocation --> $musicFilePath\n";
									}
									copy($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not copy file located at $sourceFileLocation\n" && &printerror("Error copying $sourceFileLocation -> $musicFilePath\n");
								}
								else {
									if($verbose){
										print "Moving $sourceFileLocation --> $musicFilePath\n";
									}
									move($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not move file located at $sourceFileLocation\n" && &printerror("Error moving $sourceFileLocation -> $musicFilePath\n");
								}	
							}
							else {
								#prints out exactly what is going on, --verbose
								if($verbose){
									print "Old file is of higer or equal bitrate, Skipping.\n";
								}
							}
						}
						else{
						
							my $filesize = -s $musicFilePath;
							my $new_filesize = -s $sourceFileLocation;
							if($new_filesize > $filesize){
								if($verbose){
									print "New file size of "  . $new_filesize . " is > than " . $filesize . " Replacing\n";
								}
								if($moveFile == 0) {
									if($verbose){
										print "Copying $sourceFileLocation --> $musicFilePath\n";
									}
									copy($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not copy file located at $sourceFileLocation\n" && &printerror("Error copying $sourceFileLocation -> $musicFilePath\n");
								}
								else {
									if($verbose){
										print "Moving $sourceFileLocation --> $musicFilePath\n";
									}
									move($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not move file located at $sourceFileLocation\n" && &printerror("Error moving $sourceFileLocation -> $musicFilePath\n");
								}
							}
							else {
								#print"Old file is of higher or equal size, Skipping.\n";
								if($verbose){
									&printerror("[SKIP] Replacement is lower quality than $musicFilePath\n");
									print "Old file is of higer or equal bitrate, Skipping.\n";
								}
							}
						}
					}
				}
				else {
					if($moveFile == 0) {
						if($verbose){
							print "Copying $sourceFileLocation --> $musicFilePath\n";
						}
						copy($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not copy file located at $sourceFileLocation\n" && &printerror("Error copying $sourceFileLocation -> $musicFilePath\n");
					}
					else {
						if($verbose){
							print "Moving $sourceFileLocation --> $musicFilePath\n";
						}
						move($sourceFileLocation, "$musicFilePath") or warn "*ERROR could not move file located at $sourceFileLocation\n" && &printerror("Error moving $sourceFileLocation -> $musicFilePath\n");
					}
				}
			}
		}
	}
	
	print color 'Bold Green' if $operating_system =~ m/(linux|darwin)/i;
	print "\nDone creating and populating directories!\n";
	print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
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
				}
			}
		}
	}
	#After were done removing, lets go ahead and remove those empty hashes.
	&cleanartist();
}

#Print Menu
sub preprint{
	print "You may enter any text to match.  To search for bitrate use a < or > followed by the bitrate (ie > 128).\n";
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
					push (@attributes, "$value") if $forthkey eq "size";
					push(@attributes, "$value") if $forthkey eq "filetype";
					
					push(@attributes, "\"$value\"") if $forthkey eq "path" && $inc;
				}
				push(@toprint, "$firstkey - $secondkey -> $thirdkey\n@attributes\n");
			}
		}
	}
	return @toprint;
}
###################
# Charles Lundblad
###################
#Prompt for file to write sql script to.
sub presql {

	print "Enter the name of the SQL script: ";
	my $file = <STDIN>; chomp($file);
	&sql($file) unless $file eq "q";
}
#Build sql statement.
sub sql {
	my $SQL_file = &spaces(shift);

	print "\n\nGenerating SQL Script: $SQL_file\n";
	open (MYFILE, ">>$SQL_file") or warn "Could not open file to write!" && &printerror("Could not open SQL Script to write to! Location $SQL_file\n");
	print MYFILE "-- This script will create the database music_database\n";
	print MYFILE "-- and will also populate the table with your music list\n";
	print MYFILE "CREATE DATABASE `music_database` ;\n";
	print MYFILE "USE music_database;\n";
	print MYFILE "CREATE TABLE `music_database`.`music_list` (\n";
	print MYFILE "`id` INT NOT NULL AUTO_INCREMENT PRIMARY KEY ,\n";
	print MYFILE "`artist` VARCHAR( 255 ) NOT NULL ,\n";
	print MYFILE "`album` VARCHAR( 255 ) NOT NULL ,\n";
	print MYFILE "`title` VARCHAR( 255 ) NOT NULL ,\n";
	print MYFILE "`track_number` VARCHAR( 255 ) NOT NULL ,\n";
	print MYFILE "`bitrate` INT NOT NULL ,\n";
	print MYFILE "`file_extension` VARCHAR( 10 ) NOT NULL,\n";
	print MYFILE "`path` VARCHAR( 255 ) NOT NULL\n";
	print MYFILE ") ENGINE = MYISAM ;\n";
	
	for my $artistName (keys %artists) {
		my $artistDirectory = &sanitize($artistName);

		for my $albumName (keys %{$artist_ref->{$artistName}} ) {
			my $albumDirectory = &sanitize($albumName);

			for my $song (keys %{$artist_ref->{$artistName}->{$albumName}} ) {
				my $trackTitle = &sanitize($song);
				my $sourceFileLocation = $artists{$artistName}{$albumName}{$song}{"path"};
				my $file_extension = $artists{$artistName}{$albumName}{$song}{"filetype"};
				my $trackno = $artists{$artistName}{$albumName}{$song}{"track"};
				my $new_file_bitrate = $artists{$artistName}{$albumName}{$song}{"bitrate"};
				my $filename;
				my $filePath;
				
				if(defined($trackno)) {
					$filename = $trackno . " - " . $trackTitle . ".$file_extension";
				}
				else {
					$filename = $trackTitle. "." . lc($file_extension);
					$trackno = "NULL";
				}
				
				$filePath = "$artistDirectory/$albumDirectory/$filename";
				
				
				if(!defined($new_file_bitrate) || $new_file_bitrate == 0) {
					
					$new_file_bitrate = "NULL";
				}

				if($verbose){
					print "Adding $sourceFileLocation --> $SQL_file\n";
				}
				
				if(defined($artistDirectory) && $artistDirectory ne "" && defined($albumDirectory) && $albumDirectory ne "" && defined($trackTitle) && $trackTitle ne ""){
					print MYFILE "INSERT INTO `music_database`.`music_list` (
							`artist` ,
							`album` ,
							`title`,
							`track_number` ,
							`bitrate` ,
							`file_extension`,
							`path`)
							VALUES (\"". $artistDirectory .
							"\", \"" . $albumDirectory .
							"\", \"" . $trackTitle .
							"\", \"" . $trackno .
							"\", \"" . $new_file_bitrate .
							"\", \"" . $file_extension .
							"\", \"" . $filePath .
							"\");\n";
				}
			}
		}
	}
	
	close (MYFILE); 
	print color 'Bold Green' if $operating_system =~ m/(linux|darwin)/i;
	print "\nDone creating SQL Script!\n";
	print color 'reset' if $operating_system =~ m/(linux|darwin)/i;
}