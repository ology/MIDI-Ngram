#!perl
use Test::More;
use Test::Exception;

use_ok 'MIDI::Ngram';

my $obj;

throws_ok {
    $obj = MIDI::Ngram->new
} qr/Missing required arguments: file/, 'file required';

throws_ok {
    $obj = MIDI::Ngram->new( file => 'foo' )
} qr/File foo does not exist!/, 'bogus file';

$obj = MIDI::Ngram->new(
    file => 'eg/twinkle_twinkle.mid',
    size => 3,
);
isa_ok $obj, 'MIDI::Ngram';

$obj->process;

my $expected = {
    0 => [
        '67 52 67',
        '62 55 60',
        '48 60 67',
        '48 64 62',
        '50 65 64',
        '52 65 50',
        '52 67 65',
        '52 67 69',
        '53 62 55',
        '53 65 64',
    ]
};

is_deeply $obj->notes, $expected, 'processed ordered notes';

$obj = MIDI::Ngram->new(
    file   => 'eg/twinkle_twinkle.mid',
    size   => 3,
    weight => 1,
);

isa_ok $obj, 'MIDI::Ngram';

$obj->process;

$expected = {
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

$obj->populate;

done_testing();
