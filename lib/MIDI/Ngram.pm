package MIDI::Ngram;

# ABSTRACT: Find the top repeated note phrases of a MIDI file

our $VERSION = '0.1103';

use Moo;
use strictures 2;
use namespace::clean;

use Carp;
use Lingua::EN::Ngram;
use List::Util qw( shuffle );
use List::Util::WeightedChoice qw( choose_weighted );
use MIDI::Simple;
use MIDI::Util;
use Music::Gestalt;
use Music::Note;

=head1 SYNOPSIS

  use MIDI::Ngram;

  # Analyze a tune and build a new MIDI file of repetitions
  my $mng = MIDI::Ngram->new(
    in_file      => [ 'eg/twinkle_twinkle.mid' ],
    ngram_size   => 3,
    patches      => [qw( 68 69 70 71 72 73 )],
    random_patch => 1,
    bounds       => 1,
  );

  my $analysis = $mng->process;
  print $analysis;

  my $playback = $mng->populate;

  $mng->write;

  # Analyze multitrack tunes
  $mng = MIDI::Ngram->new(
    in_file     => [ '/multi/channel/tune1.mid', '/multi/channel/tune2.mid' ],
    ngram_size  => 3,
    one_channel => 1,
  );

  $mng->process;

  # Dump out the phrases in order
  print Dumper [
    map { "$_ => " . $mng->notes->{0}{$_} }
      sort { $mng->notes->{0}{$a} <=> $mng->notes->{0}{$b} }
        keys %{ $mng->notes->{0} }
  ];

  # Inspect the phrase transition network
  print Dumper $mng->net;

=head1 DESCRIPTION

C<MIDI::Ngram> parses a given list of MIDI files, finds the top
repeated note phrases, outputs the analysis, transition network, and
renders them to a MIDI file if desired.

=head1 ATTRIBUTES

=head2 in_file

Required.  An ArrayRef of MIDI files to process.

=cut

has in_file => (
    is       => 'ro',
    isa      => \&_is_list,
    required => 1,
);

=head2 ngram_size

Ngram phrase size.

Default: C<2>

=cut

has ngram_size => (
    is      => 'ro',
    isa     => \&_is_integer,
    default => sub { 2 },
);

=head2 max_phrases

The maximum number of phrases to analyze/play.

Default: C<10>

=cut

has max_phrases => (
    is      => 'ro',
    isa     => \&_is_integer0,
    default => sub { 10 },
);

=head2 bpm

Beats per minute.

Default: C<100>

=cut

has bpm => (
    is      => 'ro',
    isa     => \&_is_integer,
    default => sub { 100 },
);

=head2 durations

The note durations to choose from (at random).

Default: C<[hn qn en]>

=cut

has durations => (
    is      => 'ro',
    isa     => \&_is_list,
    default => sub { [qw( hn qn en )] },
);

=head2 patches

The patches to choose from (at random) if given the B<random_patch> option.

Default: C<[0 .. 127]>

=cut

has patches => (
    is      => 'ro',
    isa     => \&_is_list,
    default => sub { [ 0 .. 127 ] },
);

=head2 out_file

MIDI output file.

Default: C<midi-ngram.mid>

=cut

has out_file => (
    is      => 'ro',
    default => sub { 'midi-ngram.mid' },
);

=head2 pause_duration

Insert a rest of the given duration after each phrase.

Default: C<''> (no resting)

=cut

has pause_duration => (
    is      => 'ro',
    isa     => sub { croak 'Invalid duration' unless $_[0] eq '' || $_[0] =~ /^[a-z]+$/ },
    default => sub { '' },
);

=head2 analyze

ArrayRef of the channels to analyze.  If not given, all channels are analyzed.

Default: C<undef>

=cut

has analyze => (
    is  => 'ro',
    isa => \&_is_list,
);

=head2 loop

The number of times to choose a weighted phrase.  * This only works
in conjunction with the B<weight> option.

Default: C<10>

=cut

has loop => (
    is      => 'ro',
    isa     => \&_is_integer,
    default => sub { 10 },
);

=head2 weight

Boolean.  Play phrases according to the probability of their
repetition occurrence with the function
L<List::Util::WeightedChoice/choose_weighted>.

Default: C<0>

=cut

has weight => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 random_patch

Boolean.  Choose a random patch from B<patches> for each channel.

Default: C<0> (meaning "use the piano patch")

=cut

has random_patch => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 shuffle_phrases

Boolean.  Shuffle the non-weighted phrases before playing them.

Default: C<0>

=cut

has shuffle_phrases => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 single_phrases

Boolean.  Allow single occurrence ngrams.

Default: C<0>

=cut

has single_phrases => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 one_channel

Boolean.  Accumulate phrases onto a single channel.

Default: C<0>

=cut

has one_channel => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 bounds

Boolean.  Include pitch range in the analysis.

Default: C<0>

=cut

has bounds => (
    is      => 'ro',
    isa     => \&_is_boolean,
    default => sub { 0 },
);

=head2 score

The score object in L<MIDI::Simple/"MAIN-ROUTINES">.  Constructed at
runtime.

=cut

has score => (
    is       => 'rw',
    init_arg => undef,
    lazy     => 1,
);

=head2 notes

The hash-reference bucket of ngrams.  Constructed by the B<process>
method.

=cut

has notes => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { {} },
);

=head2 net

A hash-reference ngram transition network.  Constructed by the
B<process> method.

=cut

has net => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { {} },
);

=head1 METHODS

=head2 new

  $mng = MIDI::Ngram->new(%arguments);

Create a new C<MIDI::Ngram> object.

=head2 process

  $analysis = $mng->process;

Find all ngram phrases and return the note analysis.

=cut

sub process {
    my ($self) = @_;

    my $analysis;

    for my $file ( @{ $self->in_file } ) {
        # Counter for the tracks seen
        my $i = 0;

        my $opus = MIDI::Opus->new({ from_file => $file });

        $analysis .= "Ngram analysis of $file:\n\tN\tReps\tPhrase\n";

        # Handle each track...
        for my $t ( $opus->tracks ) {
            # Collect the note events for each track
            my @events = grep {
                $_->[0] eq 'note_on'    # Only consider note_on events
                && $_->[2] != 9         # Avoid the drum channel
                && $_->[4] != 0         # Ignore events of velocity 0
            } $t->events;

            # XXX Assume that there is one channel per track
            my $track_channel = $self->one_channel ? 0 : $events[0][2];

            # Skip if there are no events and no channel
            next unless @events && defined $track_channel;

            # Skip if this is not a channel to analyze
            next if $self->analyze && keys @{ $self->analyze }
                && !grep { $_ == $track_channel } @{ $self->analyze };

            $i++;
            $analysis .= "Track $i. Channel: $track_channel\n";

            # Declare the notes to inspect
            my $text = '';

            my @group;
            my $last;

            # Accumulate the notes
            for my $event ( @events ) {
                # Transliterate MIDI note numbers to alpha-code
                ( my $str = $event->[3] ) =~ tr/0-9/a-j/;
                $text .= "$str ";

                if (@group == $self->ngram_size) {
                    my $group = join ' ', @group;
                    $self->net->{ $last . '-' . $group }++ if $last;
                    $last = $group;
                    @group = ();
                }
                push @group, $event->[3];
            }

            # Parse the note text into ngrams
            my $ngram  = Lingua::EN::Ngram->new( text => $text );
            my $phrase = $ngram->ngram( $self->ngram_size );

            # Counter for the ngrams seen
            my $j = 0;

            # Display the ngrams in order of their repetition amount
            for my $p ( sort { $phrase->{$b} <=> $phrase->{$a} || $a cmp $b } keys %$phrase ) {
                # Skip single occurance phrases if requested
                next if !$self->single_phrases && $phrase->{$p} == 1;

                # Don't allow phrases that are not the right size
                my @items = grep { $_ } split /\s+/, $p;
                next unless @items == $self->ngram_size;

                $j++;

                # End if a max is set and we are past the maximum
                last if $self->max_phrases > 0 && $j > $self->max_phrases;

                # Transliterate our letter code back to MIDI note numbers
                ( my $num = $p ) =~ tr/a-j/0-9/;

                # Convert MIDI numbers to named notes.
                my $text = _convert($num);

                $analysis .= sprintf "\t%d\t%d\t%s %s\n", $j, $phrase->{$p}, $num, $text;

                # Save the number of times the phrase is repeated
                $self->notes->{$track_channel}{$num} += $phrase->{$p};
            }

            $analysis .= $self->_gestalt_analysis( \@events )
                if $self->bounds;
        }
    }

    return $analysis;
}

sub _gestalt_analysis {
    my ( $self, $events ) = @_;

    my $score_r = MIDI::Score::events_r_to_score_r( $events );
    $score_r = MIDI::Score::sort_score_r($score_r);

    my $g = Music::Gestalt->new( score => $score_r );

    my $note = Music::Note->new( $g->PitchLowest, 'midinum' );
    my $low  = $note->format('midi');
    $note    = Music::Note->new( $g->PitchHighest, 'midinum' );
    my $high = $note->format('midi');
    $note    = Music::Note->new( $g->PitchMiddle, 'midinum' );
    my $mid  = $note->format('midi');

    my $bounds = "\tRange: $low to $high\n"
        . "\tSpan: $mid +/- " . $g->PitchRange . "\n";

    return $bounds;
}

=head2 populate

  $playback = $mng->populate;

Add notes to the MIDI score and return the playback notes.

=cut

sub populate {
    my ($self) = @_;

    my $score = MIDI::Util::setup_score( bpm => $self->bpm );
    $self->score($score);

    my @phrases;
    my $playback;

    if ( $self->weight ) {
        $playback = "Weighted playback:\n\tLoop\tChan\tPhrase\n";

        for my $channel ( sort { $a <=> $b } keys %{ $self->notes } ) {
            # Create a function that adds notes to the score
            my $func = sub {
                my $patch = $self->random_patch ? $self->_random_patch() : 0;

                MIDI::Util::set_chan_patch( $self->score, $channel, $patch );

                for my $n ( 1 .. $self->loop ) {
                    my $choice = choose_weighted(
                        [ keys %{ $self->notes->{$channel} } ],
                        [ values %{ $self->notes->{$channel} } ]
                    );

                    # Convert MIDI numbers to named notes.
                    my $text = _convert($choice);

                    $playback .= "\t$n\t$channel\t$choice $text\n";

                    # Add each chosen note to the score
                    for my $note ( split /\s+/, $choice ) {
                        # XXX This is not sophisticated at all
                        my $duration = $self->durations->[ int rand @{ $self->durations } ];
                        $self->score->n( $duration, $note );
                    }

                    $self->score->r( $self->pause_duration )
                        if $self->pause_duration;
                }
            };

            push @phrases, $func;
        }
    }
    else {
        my $type = $self->shuffle_phrases ? 'Shuffled' : 'Ordered';
        $playback = "$type playback:\n\tN\tChan\tPhrase\n";

        my $n = 0;

        for my $channel ( keys %{ $self->notes } ) {
            my $notes = $self->notes->{$channel};

            # Shuffle the phrases if requested
            my @track_notes = $self->shuffle_phrases
                ? shuffle keys %$notes
                : sort { $notes->{$b} <=> $notes->{$a} || $a cmp $b } keys %$notes;

            # Temporary list of all the phrase notes
            my @all;

            # Add the notes to a bucket
            for my $phrase ( @track_notes ) {
                $n++;

                # Convert MIDI numbers to named notes.
                my $text = _convert($phrase);

                $playback .= "\t$n\t$channel\t$phrase $text\n";

                my @phrase = split /\s/, $phrase;
                push @all, @phrase;
                push @all, 'r'
                    if $self->pause_duration;
            }

            # Create a function that adds our bucket of notes to the score
            my $func = sub {
                my $patch = $self->random_patch ? $self->_random_patch() : 0;

                MIDI::Util::set_chan_patch( $self->score, $channel, $patch);

                for my $note ( @all ) {
                    if ( $note eq 'r' ) {
                        $self->score->r( $self->pause_duration );
                    }
                    else {
                        # XXX This is not sophisticated at all
                        my $duration = $self->durations->[ int rand @{ $self->durations } ];
                        $self->score->n( $duration, $note );
                    }
                }
            };

            push @phrases, $func;
        }
    }

    $self->score->synch(@phrases);

    return $playback;
}

=head2 write

  $mng->write;

Write out the MIDI file.

=cut

sub write {
    my ($self) = @_;
    $self->score->write_score( $self->out_file );
}

sub _random_patch {
    my ($self) = @_;
    return $self->patches->[ int rand @{ $self->patches } ];
}

# Convert MIDI numbers to named notes.
sub _convert {
    my $string = shift;

    my $text = '( ';

    for my $n ( split /\s+/, $string ) {
        my $note = Music::Note->new( $n, 'midinum' );
        $text .= $note->format('midi') . ' ';
    }

    $text .= ')';

    return $text;
}

sub _is_integer0 {
    croak 'Not greater than or equal to zero'
        unless defined $_[0] && $_[0] =~ /^\d+$/;
}

sub _is_integer {
    croak 'Invalid integer'
        unless defined $_[0] && $_[0] =~ /^\d+$/ && $_[0] > 0;
}

sub _is_list {
    croak 'Invalid list'
        unless ref $_[0] eq 'ARRAY';
}

sub _is_boolean {
    croak 'Invalid Boolean'
        unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 );
}

1;
__END__

=head1 TO DO

Preserve note durations instead of random assignment.

=head1 SEE ALSO

L<Moo>

L<Lingua::EN::Ngram>

L<List::Util>

L<List::Util::WeightedChoice>

L<Music::Note>

L<MIDI::Simple>

L<MIDI::Util>

L<Music::Gestalt>

=cut
