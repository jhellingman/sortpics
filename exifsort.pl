#!/usr/bin/env perl

use 5.010; # minimum Perl version 5.010 "five-ten"

use warnings;
use strict;

# ------------------------------------------------------------
# SHARED LIBRARIES
# ------------------------------------------------------------

# You will need to install the non-core libraries yourself.
# Those are Image::ExifTool, File::Util, and Try::Tiny

use Image::ExifTool;
use File::Util;
use File::Copy 'move';
use Try::Tiny;
use Getopt::Long;
use Digest::MD5 'md5_hex';
use File::Basename 'basename';

# ------------------------------------------------------------
# THE SETUP
# ------------------------------------------------------------

# set default parameters, get user input, validate input

my $opts =
{
   src   => undef,
   dest  => undef,
   force => 0,
   test  => undef,
   help  => undef,
};

GetOptions
(
   'src|s=s'  => \$opts->{src},
   'dest|d=s' => \$opts->{dest},
   'force|f'  => \$opts->{force},
   'test|t'   => \$opts->{test},
   'help|h|?' => \$opts->{help},
) or die usage();

print usage() and exit if $opts->{help} || ! $opts->{dest} || ! $opts->{src};

die qq("$opts->{src}" is either not a directory or not writable by you.)
   if defined $opts->{src} && ( ! -w $opts->{src} || ! -d $opts->{src} );

# ------------------------------------------------------------
# PROGRAM EXECUTION (it really is this simple)
# ------------------------------------------------------------

# File::Util will let us do easy directory traversal.  Configure the
# $ftl object to warn on errors instead of die in the middle of the
# program when there might still be files to process

my $ftl = File::Util->new( { onfail => 'warn' } );

# clean up the destination path.  We have to be careful with paths that
# are simply "." or "./" because when joined to the date-based directory
# tree they could otherwise become something quite different like:
# ".YYYY/MM/DD" or ".//YYYY/MM/DD" or "/YYYY/MM/DD"

$opts->{dest} =~ s(^\./)();

$opts->{dest} =~ s(/+$)() unless $opts->{dest} eq '/';

# moving photos and movies to the root directory would almost certainly
# be a mistake.  I just decided to disallow it.

die qq(Moving photos to "/" is not supported\n) if $opts->{dest} =~ /^\/+$/;

# this kicks off the directory traversal, executing the file relocation
# callback for every subdirectory it encounters:

$ftl->list_dir( $opts->{src} => { recurse  => 1, callback => \&move_files } );

# ------------------------------------------------------------
# SUBROUTINES (most of the logic is here)
# ------------------------------------------------------------

# This is just the help message:

sub usage { <<'__USAGE__' }
USAGE:
   exifsort --src ./path/to/source/ --dest ./path/to/dest/ --test --force

DESCRIPTION:
   exifsort organizes pictures and movies into a date-based directory hierarchy
   derived from the embedded EXIF data in the actual media files themselves.

   The directory hierarchy may or may not already exist.  The layout is
   compatible with shotwell and f-spot.  It looks like this: $TARGET/YYYY/MM/DD

ARGUMENTS AND FLAGS:
   -s, --src      Path to the directory that contains the images/movies that
                  you want to sort into an organized destination directory

   -d, --dest     Path to the directory where the date-based organized
                  directory tree begins.  Example: /home/tommy/media

   -t, --test     Don't actually move any files.  Just show on the terminal
                  screen what exifsort would have done.

   -f, --force    make exifsort overwrite files in destination directories
                  that have the same name as the source file.  By default,
                  exifsort won't overwrite files with the same name
__USAGE__

# This is the callback used by File::Util when traversing the source
# directory tree looking for images recursively.  It stitches together
# the two primary tasks of this program, which are to identify EXIF dates
# and then move files around to where they are supposed to go.

sub move_files
{
   my ( $selfdir, $subdirs, $files ) = @_;

   move_file_by_date( $_ => get_exif_date( $_ ) ) for @$files;
}

# This sub uses Image::ExifTool to pull relevant time stamps out of
# the image/movie files.  First it tries to get the original date
# that the picture/movie was taken.  Failing that it tries to get
# the last-modified date timestamp from EXIF, and then the file.
# * This method does not take into account time zones.

sub get_exif_date
{
   my $file = shift;

   my $exift = Image::ExifTool->new;

   $exift->ExtractInfo( $file );
   
   #printf qq{DateTimeOriginal: %s\n}, $exift->GetValue( DateTimeOriginal => $file ) || "";
   #printf qq{DateAcquired: %s\n}, $exift->GetValue( DateAcquired => $file ) || "";
   #printf qq{FileModifyDate: %s\n}, $exift->GetValue(FileModifyDate => $file ) || "";

   my $date = $exift->GetValue( DateTimeOriginal => $file );
   
   $date ||= $exift->GetValue( DateAcquired => $file );

   $date ||= $exift->GetValue( FileModifyDate => $file );
      
   # Fix bad EXIF dates.
   unless ( !$date ) {
      $date =~ s/\//\:/g;
   }

   unless ( $date )
   {
      $date = ( stat $file )[ 8 ];

      my ( $y, $m, $d ) = ( localtime ( $date ) )[ 3, 4, 5 ];

      $m += 1;
      $y += 1900;

      # this normalizes to the format we are already getting from EXIF
      $date = join ':', $y, $m, $d;
   }

   return $date;
}

# Based on the date of the file, move it to a YYYY/MM/DD file heirarchy
# under the $opts->{dest} directory.  If running in test mode, just
# print out what would have been done if you were not.  Handles same-name
# files with care (you have to use -f or --force to overwrite)

sub move_file_by_date
{
   my ( $src_file, $date ) = @_;

   my ( $y, $m, $d ) = $date =~ /^(\d+):(\d+):(\d+)/;

   my $date_tree = sprintf '%d/%02d/%02d', $y, $m, $d;

   my $dest_dir  = $opts->{dest};

   if ( $dest_dir eq '.' || $dest_dir eq '' )
   {
      $dest_dir = './' . $date_tree;
   }
   else
   {
      $dest_dir = $dest_dir . '/' . $date_tree;
   }

   try
   {
      my $dest_file = $dest_dir . '/' . basename $src_file;

      if ( -e $dest_file && ! $opts->{force} )
      {
         printf qq{!! "%s" ALREADY EXISTS.  WON'T OVERWRITE WITHOUT --force\n},
            $dest_file;

         my $src_sum = md5_hex( $ftl->load_file( $src_file ) );
         my $dst_sum = md5_hex( $ftl->load_file( $dest_file ) );

         printf qq{   ...SOURCE: %s\n}, $src_sum;
         printf qq{   .....DEST: %s\n}, $dst_sum;

         print $src_sum eq $dst_sum
            ? "   ...RESULT: SAME\n\n"
            : "   ...RESULT: DIFFERENT\n\n"
      }
      else
      {
         printf qq{%-80s => TESTING - NOT MOVED TO %s\n}, $src_file, $dest_dir
            and return if $opts->{test};

         $ftl->make_dir( $dest_dir => { if_not_exists => 1, onfail => 'die' } );

         move $src_file, $dest_file or die $!;

         printf qq{%-80s => MOVED TO %s\n}, $src_file, $dest_dir;
      }
   }
   catch
   {
      printf qq{%-80s => FAILED TO MOVE FILE!\n}, $src_file, $y, $m, $d;

      warn $_;
   }
}

