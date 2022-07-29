#!/usr/bin/perl -w

#
# Sort pictures, based on their EXIF data.
#

use strict;
use File::Basename;
use File::Temp;
use File::Copy;
use File::stat;
use Time::localtime;
# use Image::Magick;
use Image::ExifTool;
use Getopt::Long;

my $dryRun = 0;
my $daysOffset = 0;                 # Offset to date, to deal with wrongly set cameras.
my $useModel = 0;                   # Use Make/Model in the directory structure.
my $outputPath = "SortPics-Output"; # Base directory for copied files.
my $filter = "";                    # Filer on Brand/Model.
my $sidecarExtension = ".xmp";      # Extention on sidecar files (containing metadata).

GetOptions(
    't'   => \$dryRun,
    'o=i' => \$daysOffset,
    'm'   => \$useModel,
    'f=s' => \$filter,
    'p=s' => \$outputPath);

my $errorCount = 0;
my $picturesHandled = 0;

my %modelMap = (
    "iPhone 6"                      => "Apple/iPhone 6",        # Bebie (vader Frank)

    "Canon PowerShot A3100 IS"      => "Canon/A3100IS",         # Lyn
    "Canon PowerShot A480"          => "Canon/A480",            # Bebie
    "Canon PowerShot A520"          => "Canon/A520",            # Lyn / Raphael
    "Canon PowerShot A580"          => "Canon/A580",            #
    "Canon PowerShot A60"           => "Canon/A60",             #
    "Canon EOS 1000D"               => "Canon/EOS_1000D",       # Pieter & Lida
    "Canon EOS 350D DIGITAL"        => "Canon/EOS_350D",        # Jeroen
    "Canon EOS 80D"                 => "Canon/EOS_80D",         # Jeroen
    "Canon DIGITAL IXUS 100 IS"     => "Canon/IXUS_100IS",      # Lyn
    "Canon IXUS 105"                => "Canon/IXUS_105",        # Papa & JR
    "Canon IXUS 132"                => "Canon/IXUS_132",        # Gilbert
    "Canon IXUS 240 HS"             => "Canon/IXUS_240HS",      # Lyn
    "Canon PowerShot SX700 HS"      => "Canon/SX700HS",         # Bebie (vader Frank)
    "Canon PowerShot SX710 HS"      => "Canon/SX710HS",         # Jeroen
    "Canon PowerShot SX720 HS"      => "Canon/SX720HS",         # Lyn (nieuw)
    "Canon EOS DIGITAL REBEL XT"    => "Canon/Rebel_XT",        # Gus V.

    "KODAK CX7430 ZOOM DIGITAL CAMERA"  => "Kodak/CX7430",      # ?
    "EX-Z5"                         => "Casio/EX-Z5",           #
    "EX-Z77"                        => "Casio/EX-Z77",          #
    "A735"                          => "GE/A735",               # GE A735
    "A706_ROW"                      => "Lenovo/A706",           # Via Martin
    "DiMAGE Z2"                     => "Minolta/DiMAGE_Z2",     # Pieter & Lida
    "NIKON D1X"                     => "Nikon/D1X",             # Via Martin
    "NIKON D70"                     => "Nikon/D70",             # (Manila)
    "2700 classic"                  => "Nokia/2700",            # Telefoon Jeroen
    "6151"                          => "Nokia/6151",            # Joshua (?)
    "E5-00"                         => "Nokia/E5-00",           # Filipijnen
    "DMC-FZ38"                      => "Panasonic/DMC-FZ38",    # Joshua (Barcelona)
    "<VLUU L830  / Samsung L830>"   => "Samsung/L830",          # Frank & Bebie
    "<KENOX S630  / Samsung S630>"  => "Samsung/S630",          # Roy
    "SM-G900F"                      => "Samsung/SM-G900F",      # Joshua (?)
    "C2105"                         => "Sony/C2105",            # Sony telefoon
    "SLIMLINE X5"                   => "Traveler/Slimline_X5",  # Via Bebie (Ruth)

    "Other"                         => "Other"
);



sub main();

main();

sub main() {
    ## initial call ... $ARGV[0] is the first command line argument
    list_recursively($ARGV[0]);

    print "Number of pictures:        $picturesHandled\n";
    if ($errorCount > 0) {
        print "Number of errors:          $errorCount\n";
    }
}

sub list_recursively($);

sub list_recursively($) {
    my ($directory) = @_;
    my @files = (  );

    unless (opendir(DIRECTORY, $directory)) {
        logError("Cannot open directory $directory!");
        exit;
    }

    # Read the directory, ignoring special entries "." and ".."
    @files = grep (!/^\.\.?$/, readdir(DIRECTORY));

    closedir(DIRECTORY);

    my @sortedFiles = sort @files;

    foreach my $file (@sortedFiles) {
        if (-f "$directory/$file") {
            handle_file("$directory/$file");
        } elsif (-d "$directory/$file") {
            list_recursively("$directory/$file");
        }
    }
}

sub handle_file($) {
    my ($file) = @_;

    if ($file =~ m/^(.*)\.(jpg|jpeg|avi|mov|cr2|mp4)$/i) {
        my $path = $1;
        my $extension = $2;
        my $base = basename($file, '.' . $extension);

#        my $image = Image::Magick->new();
#        $image->Read($file);
#        my $model = $image->Get('format', '%[EXIF:Model]');
#        my $date = $image->Get('format', '%[EXIF:DateTime]');

        my $exifTool = Image::ExifTool->new;
        $exifTool->ExtractInfo($file);

        # For EXIF fields see: http://www.exif.org/Exif2-2.PDF

        my $make = $exifTool->GetValue(Make => $file);

        my $model = $exifTool->GetValue(Model => $file);
        if (!defined $model) {
            logMessage("No model in EXIF data found for: $file");
            $model = "Other";
        }

        my $modelDir = $modelMap{$model};
        if (!defined $modelDir) {
            logError("Unmapped camera model: '$make' - '$model'");
            $modelDir = "Other";
        }

        if ($filter ne '' && $modelDir ne $filter) {
            return;
        }

        my $date = getExifDate($exifTool, $file);
        if ($date) {
            $date =~ m/^([0-9]{4}):([0-9]{2}):([0-9]{2})/;
            my $year = $1;
            my $month = $2;
            my $day = $3;

            my $destination = "$outputPath/$year/$year" . "_$month/$year" . "_$month" . "_$day/$base.$extension";
            if ($useModel == 1) {
                $destination = "$outputPath/$modelDir/$year/$year" . "_$month/$year" . "_$month" . "_$day/$base.$extension";
            }

            if (-e "$destination") {
                logMessage("Skipping $file: output '$destination' exists.");
            } else {
                print "$file -> $destination\n";
                if ($dryRun == 0) {
                    mkdirAndCopy($file, $destination);
                }
                if (-e $file . $sidecarExtension) {
                    print "$file$sidecarExtension -> $destination$sidecarExtension.\n";
                    if ($dryRun == 0) {
                        mkdirAndCopy($file . $sidecarExtension, $destination . $sidecarExtension);
                    }
                }
                $picturesHandled++;
            }
        } else {
            logMessage("Skipping $file: no date found in EXIF data.");
        }
    }
}

sub getExifDate {
    my $exifTool = shift;
    my $file = shift;

    my $date = $exifTool->GetValue(DateTimeOriginal => $file);
    $date ||= $exifTool->GetValue(DateAcquired => $file);
    $date ||= $exifTool->GetValue(FileModifyDate => $file);

    # Fix bad EXIF dates.
    unless (!$date) {
        $date =~ s/\//\:/g;
    }

#    unless ($date) {
#        $date = ( stat $file )[8];
#        my ( $year, $month, $day ) = ( localtime ( $date ) )[3, 4, 5];
#        $month += 1;
#        $year += 1900;
#
#        # this normalizes to the format we are already getting from EXIF
#        $date = join ':', $year, $month, $day;
#    }

    return $date;
}

sub mkdirRecursive {
    my $path = shift;
    mkdirRecursive(dirname($path)) if not -d dirname($path);
    mkdir $path or die "Could not make dir $path: $!" if not -d $path;
    return;
}

sub mkdirAndCopy {
    my ($from, $to) = @_;
    mkdirRecursive(dirname($to));
    copy($from, $to) or die "Couldn't copy: $!";
    return;
}

sub logError($) {
    my $logMessage = shift;
    $errorCount++;
    print STDERR "ERROR: $logMessage\n";
}

sub logMessage($) {
    my $logMessage = shift;
    print "$logMessage\n";
}

sub formatBytes($) {
    my $num = shift;
    my $kb = 1024;
    my $mb = (1024 * 1024);
    my $gb = (1024 * 1024 * 1024);

    ($num > $gb) ? return sprintf("%d GB", $num / $gb) :
    ($num > $mb) ? return sprintf("%d MB", $num / $mb) :
    ($num > $kb) ? return sprintf("%d KB", $num / $kb) :
    return $num . ' B';
}