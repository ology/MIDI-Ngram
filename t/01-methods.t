#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Exception;

use_ok 'MIDI::Ngram';

my $obj;

throws_ok {
    $obj = MIDI::Ngram->new
} qr/Missing required arguments: in_file/, 'file required';

throws_ok {
    $obj = MIDI::Ngram->new( in_file => 'eg/twinkle_twinkle.mid' )
} qr/Invalid list/, 'invalid in_file';

$obj = new_ok 'MIDI::Ngram' => [
    in_file    => [ 'eg/twinkle_twinkle.mid' ],
    ngram_size => 3,
    weight     => 1,
];

is_deeply $obj->in_file, [ 'eg/twinkle_twinkle.mid' ], 'in_file';
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
is $obj->score, undef, 'score undef';
is_deeply $obj->notes, {}, 'notes';
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

is_deeply $obj->notes, $expected, 'processed weighted notes';

$expected = {
  '48 60 67-48 64 62' => 1,
  '48 64 62-50 65 64' => 1,
  '50 65 64-52 65 50' => 1,
  '52 65 50-52 67 65' => 1,
  '52 67 65-52 67 69' => 1,
  '52 67 69-53 62 55' => 1,
  '53 62 55-53 65 64' => 1,
  '62 55 60-48 60 67' => 1,
  '67 52 67-62 55 60' => 1,
};

is_deeply $obj->net, $expected, 'net';

$obj->populate;

isa_ok $obj->score, 'MIDI::Simple';

done_testing();
