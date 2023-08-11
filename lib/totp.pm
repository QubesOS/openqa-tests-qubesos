#!/usr/bin/perl -w
#
# 2 Factor Authentication Perl code which used the Time-based One-time Password
# Algorithm (TOTP) algorithm.
# See: http://en.wikipedia.org/wiki/Time-based_One-time_Password_Algorithm
#
# Thanks to Vijay Boyapati @ stackoverflow
# http://stackoverflow.com/questions/25534193/google-authenticator-implementation-in-perl
#
########################################################################################
#
# Copyright 2015, Gray Watson
#
# Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby
# granted provided that the above copyright notice and this permission notice appear in all copies.  THE SOFTWARE
# IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT,
# OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
# OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
# THIS SOFTWARE.
#
# By Gray Watson http://256.com/gray/
#
package totp;
use strict;
use warnings;

use Digest::HMAC_SHA1 qw/ hmac_sha1_hex /;

use base 'Exporter';
use Exporter;

our @EXPORT = qw(generate_totp);

# this is a standard for most authenticator applications
my $TIME_STEP = 30;

#######################################################################################

#
# Return the current number associated with base32 secret to be compared with user input.
#
sub generate_totp {
    my ($base32Secret) = @_;

    # For more details of this magic algorithm, see:
    # http://en.wikipedia.org/wiki/Time-based_One-time_Password_Algorithm

    # need a 16 character hex value
    my $paddedTime = sprintf("%016x", int(time() / $TIME_STEP));
    # this starts with \0's
    my $data = pack('H*', $paddedTime);
    my $key = decode_base32($base32Secret);

    # encrypt the data with the key and return the SHA1 of it in hex
    my $hmac = hmac_sha1_hex($data, $key);

    # take the 4 least significant bits (1 hex char) from the encrypted string as an offset
    my $offset = hex(substr($hmac, -1));
    # take the 4 bytes (8 hex chars) at the offset (* 2 for hex), and drop the high bit
    my $encrypted = hex(substr($hmac, $offset * 2, 8)) & 0x7fffffff;

    # the token is then the last 6 digits in the number
    my $token = $encrypted % 1000000;
    # make sure it is 0 prefixed
    return sprintf("%06d", $token);
}

#
# Decode a base32 number which is used to encode the secret.
#
sub decode_base32 {
    my ($val) = @_;

    # turn into binary characters
    $val =~ tr|A-Z2-7|\0-\37|;
    # unpack into binary
    $val = unpack('B*', $val);

    # cut off the 000 prefix
    $val =~ s/000(.....)/$1/g;
    # trim off some characters if not 8 character aligned
    my $len = length($val);
    $val = substr($val, 0, $len & ~7) if $len & 7;

    # pack back up
    $val = pack('B*', $val);
    return $val;
}
