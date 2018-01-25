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
package qubesdistribution;
use base 'distribution';
use strict;

use testapi qw(diag check_var assert_screen);

sub init {
    my ($self) = @_;
    $self->SUPER::init();
    $self->init_consoles();
}


# initialize the consoles needed during our tests
sub init_consoles {
    my ($self) = @_;


    if (check_var('BACKEND', 'qemu')) {
        $self->add_console('root-virtio-terminal', 'virtio-terminal', {});
    }

    $self->add_console('install-shell',  'tty-console', {tty => 2});
    $self->add_console('installation',   'tty-console', {tty => check_var('VIDEOMODE', 'text') ? 1 : 6});

    return;
}

# callback whenever a console is selected for the first time
sub activate_console {
    my ($self, $console) = @_;

    testapi::diag 'activate_console';
    return;
}

sub console_selected {
    my ($self, $console, %args) = @_;
    $args{await_console} //= 1;
    $args{tags}          //= $console;
    $args{ignore}        //= qr{sut|root-virtio-terminal|iucvconn|svirt|root-ssh};
    return unless $args{await_console};
    return if $args{tags} =~ $args{ignore};
    # x11 needs special handling because we can not easily know if screen is
    # locked, display manager is waiting for login, etc.
    #return ensure_unlocked_desktop if $args{tags} =~ /x11/;
    assert_screen($args{tags}, no_wait => 1);
}

1;
# vim: sw=4 et ts=4:
