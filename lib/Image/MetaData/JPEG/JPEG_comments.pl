###########################################################
# A Perl package for showing/modifying JPEG (meta)data.   #
# Copyright (C) 2004 Stefano Bettelli                     #
# See the COPYING and LICENSE files for license terms.    #
###########################################################
package Image::MetaData::JPEG;
use Image::MetaData::JPEG::Segment;
no  integer;
use strict;
use warnings;

###########################################################
# This method accepts a string and returns a list whose   #
# elements are not larger than the length limit imposed   #
# by a JPEG segment: a segment cannot have a length which #
# couldn't be written in a 2-byte unsigned integer, that  #
# is 2^16 - 1; since the byte count must be written in    #
# this space, the real comment is limited to 2^16 - 3.    #
# The length of all but the last element in the list is   #
# maximal. The input string is not changed. Note that ""  #
# maps to (""), while an undefined value maps to (). So,  #
# it is possible to specify an empty comment.             #
###########################################################
{ my $max_length = 2**16 - 3;
  sub split_comment_string {
      return () unless defined $_[0];
      map { substr $_[0], $max_length*$_, $max_length }
      0 .. (-1 + length $_[0]) / $max_length;
  }
}

###########################################################
# This method returns the number of comment segments in   #
# the picture (it should be as fast as possible).         #
###########################################################
sub get_number_of_comments {
    my ($this) = @_;
    # return the length of the output of this method
    return scalar $this->get_segments('COM');
}

###########################################################
# This method returns a list, with an element for each    #
# comment block in the file (the element contains the     #
# comment string). Note that an empty list can be retur-  #
# ned (in case there are no comment blocks).              #
###########################################################
sub get_comments {
    my ($this) = @_;
    # get the list of segment references in this file
    my $segments = $this->{segments};
    # loop over all segments, and return the appropriate
    # field of those which are comments.
    map { $_->search_record('Comment')->get_value() } 
    $this->get_segments('COM');
}

###########################################################
# This method adds one or more new comment segments to    #
# the JPEG file, based on the string passed by the user.  #
# If there is already at least one comment segment, the   #
# new segments are created right after the last one.      #
# Otherwise, the standard position search is applied.     #
# ------------------------------------------------------- #
# In case the passed string is too big (there is a 64KB   #
# limit in JPEG segments), it is broken down in smaller   #
# strings and multiple "Comment" segments are inserted in #
# the file (they are contiguous).                         #
###########################################################
sub add_comment {
    my ($this, $string) = @_;
    # create one or more comment blocks, based on the user
    # string (the string must be split if it is too long).
    my @new_comments = map { new Image::MetaData::JPEG::Segment("COM", \ $_) }
                             split_comment_string($string);
    # get the list of segment references in this file
    my $segments = $this->{segments};
    # get the list of comment indexes
    my @indexes = $this->get_segments('COM', 'INDEXES');
    # our position is right after the last comment
    my $position = @indexes ? 1 + $indexes[$#indexes] : undef;
    # if the position is still undefined, use the standard search
    $position =$this->find_new_app_segment_position() unless defined $position;
    # actually insert the comments
    splice @$segments, $position, 0, @new_comments;
}

###########################################################
# This method replaces the $index-th comment segment with #
# one or more new segments based on $string (the index of #
# the first comment segment is 0). If $string is too big  #
# (see add_comment), it is broken down and multiple seg-  #
# ments are created. If $string is undef, the comment     #
# segment is erased. If $index is out-of-bound, only a    #
# warning is printed.                                     #
###########################################################
sub set_comment {
    my ($this, $index, $string) = @_;
    # return immediately if $index is negative or undefined
    return warn "Undefined index in set_comment" unless defined $index;
    return warn "Negative index ($index) in set_comment" if $index < 0;
    # get the list of comment segment indexes
    my @indexes = $this->get_segments('COM', 'INDEXES');
    # if $index is out of bound, warn and return. 
    return warn "Index $index out of bound ($#indexes) in set_comment" 
	if ($#indexes < $index);
    # otherwise, set an index to the target comment segment
    my $position = $indexes[$index];
    # create one or more comment blocks, based on the user
    # string (the string must be split if it is too long).
    my @new_comments = map { new Image::MetaData::JPEG::Segment("COM", \ $_) }
                             split_comment_string($string);
    # get the list of segment references in this file
    my $segments = $this->{segments};
    # replace the target segment with the new segments created
    # from the user string; @new_comments is the void list if
    # $string is undefined (this stands for comment deletion).
    # Since all comments are deleted or added, but not modified,
    # there is no need to call update here!
    splice @$segments, $position, 1, @new_comments;
}

###########################################################
# This method eliminates the $index-th comment segment    #
# (first index is 0). It is only a shortcut for the more  #
# general set_comment (called with $string = undef).      #
###########################################################
sub remove_comment {
    my ($this, $index) = @_;
    # call set_comment with an undefined string
    $this->set_comment($index, undef);
}

###########################################################
# This method eliminates all comment segments currently   #
# present in the file. It does not call set_comment, but  #
# accesses the list directly (faster).                    #
###########################################################
sub remove_all_comments {
    my ($this) = @_;
    # get the list of segment references in this file
    my $segments = $this->{segments};
    # filter the list (eliminate "COM" segments)
    @$segments = grep { $_->{name} ne "COM" } @$segments;
}

###########################################################
# This method joins some comments into a single one, with #
# the supplied separation string. This utility is neces-  #
# sary because there are readers out there which do not   #
# read past the first comment. This method overwrites the #
# first comment selected by the arguments and delete the  #
# others. A warning is issued for each illegal comment    #
# index (undefined, not a number, out of range).          #
# The final comment length is checked (<64Kb).            #
# ------------------------------------------------------- #
# If no separation string is provided, it defaults to \n. #
# If no index is provided in @selection, it is assumed    #
# that the method must join all the comments into the     #
# first one, and delete the others.                       #
###########################################################
sub join_comments {
    my ($this, $separation, @selection) = @_;
    # get all the comment indexes
    my @indexes = $this->get_segments('COM', 'INDEXES');
    # get all the comment strings
    my @comments = $this->get_comments();
    # an undefined separation string defaults to "\n"
    $separation = "\n" unless defined $separation;
    # an undefined @selection stands for "all the indexes"
    @selection = 0..$#indexes unless @selection;
    # discard the elements of @selection which do not make
    # sense, and leave the others in ascending numerical order
    @selection = sort {$a <=> $b} map {
	my $error = undef;
	if    (! defined $_)         { $error = "Undefined comment index"; }
	elsif ($_ =~ /[^\d]/)        { $error = "'$_' not a whole number"; }
	elsif ($_<0 || $_>$#indexes) { $error = "index $_ out of range"; }
	warn "$error in join_comments: discarding index" if defined $error;
	defined $error ? () : $_;
    } @selection;
    # return immediately if @selection is empty
    return warn "No valid comment indexes in join_comments" unless @selection;
    # concatenate valid comments in a single string (write a copy
    # of the separation string between every two comments).
    my $joint_comment = join $separation, map { $comments[$_] } @selection;
    # extract the first comment segment index in the selection list
    # as the target segment index. Then remove all other comments;
    # be careful to remove comments starting from higher indexes!
    my $target_index = shift @selection;
    $this->remove_comment($_) for (sort {$b <=> $a} @selection);
    # replace the target comment with $joint_comment
    $this->set_comment($target_index, $joint_comment);
}

# successful package load
1;
