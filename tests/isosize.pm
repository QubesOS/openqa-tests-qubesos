# Qubes OS openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2016 SUSE LLC
# Copyright © 2018 Marek Marczykowski-Górecki
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

use base "basetest";
use strict;
use testapi;

sub run {
    my $self   = shift;
    my $iso    = get_var("ISO") || get_var('HDD_1');
    my $size   = $iso ? -s $iso : 0;
    my $result = 'ok';
    my $max    = get_var("ISO_MAXSIZE", 0);
    if (!$size || !$max || $size > $max) {
        $result = 'softfail';
    }
    if (!defined $size) {
        diag("iso path invalid: $iso");
    }
    else {
        diag("check if actual iso size $size fits $max: $result");
    }
    $self->result($result);
}

1;
# vim: set sw=4 et:
