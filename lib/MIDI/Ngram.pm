package MIDI::Ngram;

# ABSTRACT: Find the top repeated note phrases of a MIDI file

our $VERSION = '0.0101';

use Moo;
use strictures 2;
use namespace::clean;

use Carp;
use Lingua::EN::Ngram;
use List::Util qw( shuffle );
use List::Util::WeightedChoice qw( choose_weighted );
use MIDI::Simple;
use Music::Note;
use Music::Tempo;

=head1 SYNOPSIS

  use MIDI::Ngram;
  my $mng = MIDI::Ngram->new(
    file    => 'eg/twinkle_twinkle.mid',
    size    => 3,
    verbose => 1,
  );
  $mng->process;
  $mng->populate;
  $mng->write;

=head1 DESCRIPTION

C<MIDI::Ngram> parses a given MIDI file and finds the top repeated note phrases.

=head1 ATTRIBUTES

=head2 file

Required.  The MIDI file to process.

=cut

has file => (
    is       => 'ro',
    isa      => sub { croak "File $_[0] does not exist!" unless -e $_[0] },
    required => 1,
);

=head2 size

Ngram phrase size.  Default: 2

=cut

has size => (
    is      => 'ro',
    isa     => sub { croak 'Invalid integer' unless $_[0] && $_[0] =~ /^\d+$/ && $_[0] > 0 },
    default => sub { 2 },
);

=head2 max

The maximum number of phrases to play.  Default: 10

=cut

has max => (
    is      => 'ro',
    isa     => sub { croak 'Invalid integer' unless $_[0] && $_[0] =~ /^\d+$/ && $_[0] > 0 },
    default => sub { 10 },
);

=head2 bpm

Beats per minute.  Default: 100

=cut

has bpm => (
    is      => 'ro',
    isa     => sub { croak 'Invalid integer' unless $_[0] && $_[0] =~ /^\d+$/ && $_[0] > 0 },
    default => sub { 100 },
);

=head2 durations

The note durations to choose from (at random).  Default: [qn tqn]

=cut

has durations => (
    is      => 'ro',
    isa     => sub { croak 'Invalid list' unless ref $_[0] eq 'ARRAY' },
    default => sub { [qw( qn tqn )] },
);

=head2 patches

The patches to choose from (at random) if given the B<randpatch> option.
Otherwise 0 (piano) is used.  Default: [0 .. 127]

=cut

has patches => (
    is      => 'ro',
    isa     => sub { croak 'Invalid list' unless ref $_[0] eq 'ARRAY' },
    default => sub { [ 0 .. 127 ] },
);

=head2 out_file

MIDI output file.  Default: midi-ngram.mid

=cut

has out_file => (
    is      => 'ro',
    default => sub { 'midi-ngram.mid' },
);

=head2 pause

Insert a rest of the given duration after each phrase.  Default: '' (no resting)

=cut

has pause => (
    is      => 'ro',
    isa     => sub { croak 'Invalid duration' unless $_[0] eq '' || $_[0] =~ /^[a-z]+$/ },
    default => sub { '' },
);

=head2 loop

The number of times to choose a weighted phrase.  * Only works with the
B<weight> option.  Default: 4

=cut

has loop => (
    is      => 'ro',
    isa     => sub { croak 'Invalid integer' unless $_[0] && $_[0] =~ /^\d+$/ && $_[0] > 0 },
    default => sub { 10 },
);

=head2 weight

Boolean.  Play phrases by their ngram repetition occurrence.  Default: 0

=cut

has weight => (
    is      => 'ro',
    isa     => sub { croak 'Invalid Boolean' unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 ) },
    default => sub { 0 },
);

=head2 randpatch

Boolean.  Choose a random patch from B<patches> for each channel.
Default: 0 (piano)

=cut

has randpatch => (
    is      => 'ro',
    isa     => sub { croak 'Invalid Boolean' unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 ) },
    default => sub { 0 },
);

=head2 shuffle_phrases

Boolean.  Shuffle the phrases before playing them.  Default: 0

=cut

has shuffle_phrases => (
    is      => 'ro',
    isa     => sub { croak 'Invalid Boolean' unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 ) },
    default => sub { 0 },
);

=head2 single

Boolean.  Allow single occurrence ngrams.  Default: 0

=cut

has single => (
    is      => 'ro',
    isa     => sub { croak 'Invalid Boolean' unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 ) },
    default => sub { 0 },
);

=head2 verbose

Boolean.  Output progress print statements.

=cut

has verbose => (
    is      => 'ro',
    isa     => sub { croak 'Invalid Boolean' unless defined $_[0] && ( $_[0] == 1 || $_[0] == 0 ) },
    default => sub { 0 },
);

=head2 opus

The MIDI opus object.  Constructed at runtime.  Constructor argument if given
will be ignored.

=cut

has opus => (
    is       => 'ro',
    init_arg => undef,
    lazy     => 1,
    builder  => 1,
);

sub _build_opus {
    my ($self) = @_;
    my $opus = MIDI::Opus->new({ from_file => $self->file });
    return $opus;
}

=head2 score

The MIDI score object.  Constructed at runtime.  Constructor argument if given
will be ignored.

=cut

has score => (
    is       => 'rw',
    init_arg => undef,
    lazy     => 1,
);

=head2 notes

The bucket of ngrams.  Constructed at runtime.  Constructor argument if given
will be ignored.

=cut

has notes => (
    is       => 'ro',
    init_arg => undef,
    default  => sub { {} },
);

=head1 METHODS

=head2 new()

  $mng = MIDI::Ngram->new(%arguments);

Create a new C<MIDI::Ngram> object.

=head2 process()

  $mng->process;

Find all ngram phrases.

=cut

sub process {
    my ($self) = @_;

    # Counter for the tracks seen
    my $i = 0;

    print "Ngram analysis:\n\tNum\tReps\tPhrase\n"
        if $self->verbose;

    # Handle each track...
    for my $t ( $self->opus->tracks ) {
        # Collect the note events for each track except channel 9 (percussion)
        my @events = grep { $_->[0] eq 'note_on' && $_->[2] != 9 && $_->[4] != 0 } $t->events;

        my $track_channel = $events[0][2];

        # Skip if there are no events and no channel
        next unless @events && defined $track_channel;

        $i++;
        print "$t $i. channel: $track_channel\n"
            if $self->verbose;

        # Declare the notes to inspect
        my $text = '';

        # Accumulate the notes
        for my $event ( @events ) {
            # Transliterate MIDI note numbers to alpha-code
            ( my $str = $event->[3] ) =~ tr/0-9/a-j/;
            $text .= "$str ";
        }

        # Parse the note text into ngrams
        my $ngram  = Lingua::EN::Ngram->new( text => $text );
        my $phrase = $ngram->ngram( $self->size );

        # Counter for the ngrams seen
        my $j = 0;

        # Display the ngrams in order of their repetition amount
        for my $p ( sort { $phrase->{$b} <=> $phrase->{$a} || $a cmp $b } keys %$phrase ) {
            # Skip single occurance phrases if requested
            next if !$self->single && $phrase->{$p} == 1;

            # Don't allow phrases that are not the right size
            my @items = grep { $_ } split /\s+/, $p;
            next unless @items == $self->size;

            $j++;

            # End if we are past the maximum
            last if $self->max > 0 && $j > $self->max;

            # Transliterate our letter code back to MIDI note numbers
            ( my $num = $p ) =~ tr/a-j/0-9/;

            # Convert MIDI numbers to named notes.
            my $text = _convert($num);

            printf "\t%d\t%d\t%s %s\n", $j, $phrase->{$p}, $num, $text
                if $self->verbose;

            # If we are playing by weight, save the number of times the phrase is repeated
            if ( $self->weight ) {
                $self->notes->{$track_channel}{$num} = $phrase->{$p};
            }
            # Otherwise, just save the phrase itself
            else {
                push @{ $self->notes->{$track_channel} }, $num;
            }
        }
    }
}

=head2 populate()

  $mng->populate;

Add notes to the MIDI score.

=cut

sub populate {
    my ($self) = @_;

    $self->score( _setup_midi( bpm => $self->bpm ) );

    my @phrases;

    if ( $self->weight ) {
        print "Weighted playback:\n\tLoop\tChan\tPhrase\n"
            if $self->verbose;

        for my $channel ( sort { $a <=> $b } keys %{ $self->notes } ) {
            # Create a function that adds notes to the score
            my $func = sub {
                my $patch = $self->randpatch ? _random_patch() : 0;

                _set_chan_patch( $self->score, $channel, $patch );

                for my $n ( 1 .. $self->loop ) {
                    my $choice = choose_weighted(
                        [ keys %{ $self->notes->{$channel} } ],
                        [ values %{ $self->notes->{$channel} } ]
                    );

                    # Convert MIDI numbers to named notes.
                    my $text = _convert($choice);

                    print "\t$n\t$channel\t$choice $text\n"
                        if $self->verbose;

                    # Add each chosen note to the score
                    for my $note ( split /\s+/, $choice ) {
                        my $duration = $self->durations->[ int rand @{ $self->durations } ];
                        $self->score->n( $duration, $note );
                    }

                    $self->score->r( $self->pause )
                        if $self->pause;
                }
            };

            push @phrases, $func;
        }
    }
    else {
        my $type = $self->shuffle_phrases ? 'Shuffled' : 'Ordered';
        print "$type playback:\n\tN\tChan\tPhrase\n"
            if $self->verbose;

        my $n = 0;

        for my $channel ( keys %{ $self->notes } ) {
            my @all;

            # Shuffle the phrases if requested
            my @track_notes = $self->shuffle_phrases
                ? shuffle @{ $self->notes->{$channel} }
                : @{ $self->notes->{$channel} };

            # Add the notes to a bucket
            for my $phrase ( @track_notes ) {
                $n++;

                # Convert MIDI numbers to named notes.
                my $text = _convert($phrase);

                print "\t$n\t$channel\t$phrase $text\n"
                    if $self->verbose;

                my @phrase = split /\s/, $phrase;
                push @all, @phrase;
                push @all, 'r'
                    if $self->pause;
            }

            # Create a function that adds our bucket of notes to the score
            my $func = sub {
                my $patch = $self->randpatch ? _random_patch() : 0;

                _set_chan_patch( $self->score, $channel, $patch);

                for my $note ( @all ) {
                    if ( $note eq 'r' ) {
                        $self->score->r( $self->pause );
                    }
                    else {
                        my $duration = $self->durations->[ int rand @{ $self->durations } ];
                        $self->score->n( $duration, $note );
                    }
                }
            };

            push @phrases, $func;
        }
    }

    $self->score->synch(@phrases);
}

=head2 write()

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

sub _setup_midi {
    my %args = (
        volume  => 120,
        bpm     => 100,
        channel => 0,
        patch   => 0,
        octave  => 5,
        @_,
    );

    my $score = MIDI::Simple->new_score();

    $score->set_tempo( bpm_to_ms($args{bpm}) * 1000 );

    $score->Volume($args{volume});
    $score->Channel($args{channel});
    $score->Octave($args{octave});
    $score->patch_change( $args{channel}, $args{patch} );

    return $score;
}

sub _set_chan_patch {
    my ( $score, $channel, $patch ) = @_;

    $channel //= 0;
    $patch   //= 0;

    $score->patch_change( $channel, $patch );
    $score->noop( 'c' . $channel );
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

L<Music::Tempo>

=cut
