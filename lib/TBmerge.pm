#!/usr/bin/perl

=head1

        TBseq - a computational pipeline for detecting variants in NGS-data

        Copyright (C) 2016 Thomas A. Kohl, Robin Koch, Maria R. De Filippo, Viola Schleusener, Christian Utpatel, Daniela M. Cirillo, Stefan Niemann

        This program is free software: you can redistribute it and/or modify
        it under the terms of the GNU General Public License as published by
        the Free Software Foundation, either version 3 of the License, or
        (at your option) any later version.

        This program is distributed in the hope that it will be useful,
        but WITHOUT ANY WARRANTY; without even the implied warranty of
        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
        GNU General Public License for more details.

        You should have received a copy of the GNU General Public License
        along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

# tabstop is set to 8.

package TBmerge;

use strict;
use warnings;
use File::Copy;
use TBtools;
use Exporter;
use List::Util qw(max);
use vars qw($VERSION @ISA @EXPORT);

###################################################################################################################
###                                                                                                             ###
### Description: This package merge multiple mapping files for the same sample, if the sample was resequenced.	###
###                                                                                                             ###
### Input:  .bam                                                                                       		###
### Output: .bam (.bamlog or .mergelog)                                                                         ###
###                                                                                                             ###
###################################################################################################################

$VERSION	=	1.11;
@ISA		=	qw(Exporter);
@EXPORT		=	qw(tbmerge);


sub tbmerge {
	# Get parameter and input from front-end.
	my $logprint		=	shift;
	my $SAMBAMBA_dir	=	shift;
	my $BAM_OUT		=	shift;
    	my $MBAM_OUT		=	shift;
    	my $GATK_OUT		=	shift;
    	my $MPILE_OUT		=	shift;
    	my $POS_OUT		=	shift;
    	my $CALL_OUT		=	shift;
    	my $threads		=	shift;
	my @bam_files		=	@_;
	my %input;
	# Prepare input.
	foreach my $file (sort { $a cmp $b } @bam_files) {
		my @file_name		=	split(/_/,$file);
		my $sampleID		=	shift(@file_name);
		my $libID		=	shift(@file_name);
		my $machine		=	shift(@file_name);
		my $run			=	shift(@file_name);
		my $seqlength		=	shift(@file_name);
		my $samplelib		=	$sampleID."_".$libID;
		push(@{$input{$samplelib}},$file);
	}
	@bam_files = ();
	# Start logic...
	foreach my $samplelib (sort { $a cmp $b } keys %input) {
		my @bams		=	@{$input{$samplelib}};
		if(scalar(@bams) == 1) {
			print $logprint  "<INFO>\t",timer(),"\tSkipping merging workflow for $samplelib, nothing to merge!\n";
			next;
		}
		my $sampleID			=	"";
		my $libID			=	"";
		my $machine			=	"";
		my $run				=	"";
		my $seqlength			=	"";
		$seqlength			=~	s/bp//;
		my $multi_merge 		= 	0;
		my $old_multi_mergelog_file	=	"";
		my @lengths         		=	();
		foreach my $file (sort { $a cmp $b } @bams) {
			my @file_name		=	split(/_/,$file);
			$sampleID		= 	shift(@file_name);
			$libID			= 	shift(@file_name);
			$machine		= 	shift(@file_name);
			$run			= 	shift(@file_name);
			$seqlength		=	shift(@file_name);
			push(@lengths,$seqlength);
			if($machine =~ /^multi(\d+)/) {	
				$multi_merge			=	$1;
				$old_multi_mergelog_file	= 	$file;
				$old_multi_mergelog_file	=~	s/\.bam$/\.mergelog/;
			}
		}
		my $multisource					=	"multi" . scalar(@bams);
		if($multi_merge > 0) {
			my $correct_multisource_number		=	scalar(@bams) -1 + $multi_merge;
			$multisource				= 	"multi" . $correct_multisource_number;
		}
		my $date_string			=	timer();
		$date_string			=~	s/\[//;
		$date_string                    =~      s/\]//;
		$date_string                    =~      s/\-/_/g;
		$date_string                    =~      s/\:/_/g;
		$date_string                    =~      s/\s.*//;
		$date_string			=~	s/_/-/g;
		my $max_length			=	max(@lengths);
		my $multi_file			=	$sampleID . "_" . $libID . "_" . $multisource . "_" . $date_string . "_" . $max_length . ".bam";
		my $logfile			=	$sampleID . "_" . $libID . "_" . $multisource . "_" . $date_string . "_" . $max_length . ".mergelog";
		unlink("$BAM_OUT/$logfile")									|| print $logprint "<WARN>\t",timer(),"\tCan't delete $logfile: No such file!\n";
		if(-f "$BAM_OUT/$old_multi_mergelog_file") {
			cat($logprint,"$BAM_OUT/$old_multi_mergelog_file","$BAM_OUT/$logfile")			|| die print $logprint "<ERROR>\t",timer(),"\tcat failed: $!\n";
			move("$BAM_OUT/$old_multi_mergelog_file","$MBAM_OUT/$old_multi_mergelog_file") 		|| die print $logprint "<ERROR>\t",timer(),"\tmove failed: $!\n";
		}
		my $bam_string;
		foreach my $bam (sort { $a cmp $b } @bams) {
			$bam_string		.=	" $BAM_OUT/$bam";
		}
		# Merge .bam files using combined header.
		print $logprint "<INFO>\t",timer(),"\tStart merging using sambamba...\n";
		print $logprint "<INFO>\t",timer(),"\t$SAMBAMBA_dir/sambamba merge -t $threads $BAM_OUT/$multi_file $bam_string\n";
		system("$SAMBAMBA_dir/sambamba merge -t $threads $BAM_OUT/$multi_file $bam_string");
		print $logprint "<INFO>\t",timer(),"\tFinished merging using sambamba!\n";
		# Recreate index with sambamba.
		print $logprint "<INFO>\t",timer(),"\tStart recreating index using sambamba...\n";
		rint $logprint "<INFO>\t",timer(),"\t$SAMBAMBA_dir/sambamba index $BAM_OUT/$multi_file\n";
		system("$SAMBAMBA_dir/sambamba index $BAM_OUT/$multi_file");
		print $logprint "<INFO>\t",timer(),"\tFinished recreating index using sambamba!\n";
		# Moving into specific directories.
		print $logprint "<INFO>\t",timer(),"\tMoving files to certain directories...\n";
		foreach my $file (sort { $a cmp $b } @bams) {
			my $bamlog_file		=	$file . "log";
			my $bai_file		=	$file . ".bai";
			cat($logprint,"$BAM_OUT/$bamlog_file","$BAM_OUT/$logfile")	|| die print $logprint "<ERROR>\t",timer(),"\tcat failed: $!\n";
			move("$BAM_OUT/$file","$MBAM_OUT/$file")			|| die print $logprint "<ERROR>\t",timer(),"\tmove failed: $!\n";
			move("$BAM_OUT/$bamlog_file","$MBAM_OUT/$bamlog_file")		|| die print $logprint "<ERROR>\t",timer(),"\tmove failed: $!\n";
			move("$BAM_OUT/$bai_file","$MBAM_OUT/$bai_file")		|| die print $logprint "<ERROR>\t",timer(),"\tmove failed: $!\n";
		}
		# Removing existing downstream files.
		print $logprint "<INFO>\t",timer(),"\tRemoving existing downstream files...\n";
		unlink glob("$GATK_OUT/$samplelib*") 	|| print $logprint "<WARN>\t",timer(),"\tCan't delete \"GATK_Bam\" old downstream files for $samplelib: Files not found!\n";
		unlink glob("$MPILE_OUT/$samplelib*")   || print $logprint "<WARN>\t",timer(),"\tCan't delete \"Mpileup\" old downstream files for $samplelib: Files not found!\n";
		unlink glob("$POS_OUT/$samplelib*") 	|| print $logprint "<WARN>\t",timer(),"\tCan't delete \"Position_Tables\" old downstream file for $samplelib: Files not found!\n";
		unlink glob("$CALL_OUT/$samplelib*") 	|| print $logprint "<WARN>\t",timer(),"\tCan't delete \"Called\" old downstream files for $samplelib: Files not found!\n";
		# Finished.
        	print $logprint "<INFO>\t",timer(),"\tMerging finished for $samplelib!\n";
		@bams = ();
	}
	undef(%input);
}


1;
