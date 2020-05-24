#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Exception;

use_ok 'MIDI::Ngram';

my $filename = 'eg/twinkle_twinkle.mid';

throws_ok {
    MIDI::Ngram->new
} qr/Missing required arguments: in_file/, 'file required';

throws_ok {
    MIDI::Ngram->new( in_file => $filename )
} qr/Invalid list/, 'invalid in_file';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], ngram_size => 0 )
} qr/Invalid integer/, 'invalid ngram_size';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], max_phrases => -1 )
} qr/Not greater than or equal to zero/, 'invalid max_phrases';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], bpm => 0 )
} qr/Invalid integer/, 'invalid bpm';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], durations => 0 )
} qr/Invalid list/, 'invalid durations';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], patches => 0 )
} qr/Invalid list/, 'invalid patches';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], pause_duration => 0 )
} qr/Invalid duration/, 'invalid pause_duration';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], analyze => 0 )
} qr/Invalid list/, 'invalid analyze';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], loop => 0 )
} qr/Invalid integer/, 'invalid loop';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], weight => 'foo' )
} qr/Invalid Boolean/, 'invalid weight';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], random_patch => 'foo' )
} qr/Invalid Boolean/, 'invalid random_patch';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], shuffle_phrases => 'foo' )
} qr/Invalid Boolean/, 'invalid shuffle_phrases';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], single_phrases => 'foo' )
} qr/Invalid Boolean/, 'invalid single_phrases';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], one_channel => 'foo' )
} qr/Invalid Boolean/, 'invalid one_channel';

throws_ok {
    MIDI::Ngram->new( in_file => [$filename], bounds => 'foo' )
} qr/Invalid Boolean/, 'invalid bounds';

my $obj = new_ok 'MIDI::Ngram' => [
    in_file    => [$filename],
    ngram_size => 3,
    weight     => 1,
];

is_deeply $obj->in_file, [$filename], 'in_file';
is $obj->ngram_size, 3, 'ngram_size';
is $obj->max_phrases, 10, 'max_phrases';
is $obj->bpm, 100, 'bpm';
is_deeply $obj->durations, [qw(hn qn en)], 'durations';
is_deeply $obj->patches, [0 .. 127], 'patches';
is $obj->out_file, 'midi-ngram.mid', 'out_file';
ok !$obj->pause_duration, 'pause_duration';
ok !$obj->analyze, 'analyze';
is $obj->loop, 10, 'loop';
ok $obj->weight, 'weight';
ok !$obj->random_patch, 'random_patch';
ok !$obj->shuffle_phrases, 'shuffle_phrases';
ok !$obj->single_phrases, 'single_phrases';
ok !$obj->one_channel, 'one_channel';
ok !$obj->bounds, 'bounds';
is $obj->score, undef, 'score';
is_deeply $obj->notes, {}, 'notes';
is_deeply $obj->dura, {}, 'notes';
is_deeply $obj->net, {}, 'net';

$obj->process;

my $expected = {
    0 => {
        '67 52 67' => 4,
        '62 55 60' => 3,
        '48 60 67' => 2,
        '48 64 62' => 2,
        '50 65 64' => 2,
        '52 65 50' => 2,
        '52 67 65' => 2,
        '52 67 69' => 2,
        '53 62 55' => 2,
        '53 65 64' => 2,
    }
};

is_deeply $obj->notes, $expected, 'processed notes';

$expected = {
    0 => {
        'hn hn qn' => 4,
        'hn qn hn' => 8,
        'hn qn qn' => 13,
        'qn hn hn' => 5,
        'qn hn qn' => 17,
        'qn qn hn' => 13,
        'qn qn qn' => 7,
    }
};

is_deeply $obj->dura, $expected, 'processed durations';

$obj->populate;

isa_ok $obj->score, 'MIDI::Simple';

$obj = new_ok 'MIDI::Ngram' => [
    in_file    => [$filename],
    ngram_size => 2,
];

$obj->process;

$expected = {
  '50 65-64 48' => 2,
  '52 48-67 52' => 1,
  '52 65-50 65' => 2,
  '52 67-65 53' => 1,
  '52 67-69 53' => 2,
  '53 62-55 60' => 2,
  '53 65-64 55' => 1,
  '55 60-52 48' => 1,
  '55 64-62 55' => 1,
  '55 67-52 67' => 1,
  '60 48-60 67' => 2,
  '60 67-52 67' => 2,
  '62 55-60 48' => 1,
  '64 48-64 62' => 2,
  '64 55-64 62' => 1,
  '64 62-53 62' => 2,
  '64 62-55 67' => 1,
  '65 53-65 64' => 1,
  '65 64-55 64' => 1,
  '67 52-67 65' => 1,
  '67 65-53 65' => 1,
  '69 53-69 67' => 2,
  '69 67-52 65' => 2,
};

is_deeply $obj->net, $expected, 'net';

done_testing();
