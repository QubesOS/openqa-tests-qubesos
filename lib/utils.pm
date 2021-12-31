# The Qubes OS Project, https://www.qubes-os.org/
#
# Copyright (C) 2014-2017 SUSE LLC
# Copyright (C) 2018 Marek Marczykowski-Górecki <marmarek@invisiblethingslab.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
# 
package utils;
use strict;
use base 'Exporter';
use Exporter;
use testapi qw(check_screen wait_still_screen assert_screen send_key);

our @EXPORT = qw(us_colemak colemak_us assert_screen_with_keypress);

=head2 us_colemak

Translate given text to be entered with Colemak keyboard layout set.
This is to handle weird cases where VNC use us keyboard layout, but the system
have us-colemak.

=cut

sub us_colemak {
    my $input = shift;

    # lukspass: uindradd  iler;arr
    # userpass: idksradd
    #            qwertyuiopasdfghjkl;zxcvbnm
    $input =~ tr/qwfpgjluy;arstdhneiozxcvbkm/qwertyuiopasdfghjkl;zxcvbnm/;
    return $input;
}

=head2 colemak_us

Reverse us_colemak function.

=cut

sub colemak_us {
    my $input = shift;

    # lukspass: uindradd  iler;arr
    # userpass: idksradd
    #                                        qwertyuiopasdfghjkl;zxcvbnm
    $input =~ tr/qwertyuiopasdfghjkl;zxcvbnm/qwfpgjluy;arstdhneiozxcvbkm/;
    return $input;
}

sub assert_screen_with_keypress {
    my ($tag, $timeout) = @_;

    # occasionally send a key, to disable screensaver
    my $starttime = time;
    while (time - $starttime < $timeout) {
        last if check_screen($tag);
        send_key('ctrl') if wait_still_screen(7, 15);
    }
    assert_screen($tag);
}

1;
# vim: sw=4 et ts=4:
