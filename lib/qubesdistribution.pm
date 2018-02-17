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
use serial_terminal ();

use testapi qw(diag check_var assert_screen type_string type_password match_has_tag wait_serial get_var send_key);

sub init {
    my ($self) = @_;
    $self->SUPER::init();
    $testapi::password = 'userpass';
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
    $self->add_console('root-console',   'tty-console', {tty => 3});
    $self->add_console('user-console',   'tty-console', {tty => 4});
    $self->add_console('log-console', 'tty-console', {tty => 5});

    return;
}

# Make sure the right user is logged in, e.g. when using remote shells
sub ensure_user {
    my ($user) = @_;
    type_string("su - $user\n") if $user ne 'root';
}

# callback whenever a console is selected for the first time
sub activate_console {
    my ($self, $console) = @_;

    $console =~ m/^(\w+)-(console|virtio-terminal|ssh|shell)/;
    my ($name, $user, $type) = ($1, $1, $2);
    $name = $user //= '';
    $type //= '';
    if ($name eq 'user') {
        $user = $testapi::username;
    }
    elsif ($name eq 'log') {
        $user = 'root';
    }

    testapi::diag "activate_console, console: $console, type: $type";
    if ($type eq 'console') {
        my $nr = 4;
        $nr = 3 if ($name eq 'root');
        $nr = 5 if ($name eq 'log');
        my @tags = ("tty$nr-selected", "text-logged-in-$user", "text-login");
        # we need to wait more than five seconds here to pass the idle timeout in
        # case the system is still booting (https://bugzilla.novell.com/show_bug.cgi?id=895602)
        # or when using remote consoles which can take some seconds, e.g.
        # just after ssh login
        assert_screen \@tags, 60;
        if (match_has_tag("tty$nr-selected") or match_has_tag("text-login")) {
            type_string "$user\n";
            handle_password_prompt();
        }
        elsif (match_has_tag('text-logged-in-root')) {
            ensure_user($user);
        }
        assert_screen "text-logged-in-$user";
        $self->set_standard_prompt($user);
        assert_screen $console;
    }
    elsif ($type eq 'virtio-terminal') {
        serial_terminal::login($user, "$user ");
    }


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

sub handle_password_prompt {
    assert_screen "password-prompt";
    type_password();
    send_key('ret');
}

sub script_sudo($$) {
    my ($self, $prog, $wait) = @_;

    my $str = time;
    if ($wait > 0) {
        $prog = "$prog; echo $str-\$?- > /dev/$testapi::serialdev";
    }
    type_string "clear\n";    # poo#13710
    type_string "sudo sh -c \'$prog\'\n";
    handle_password_prompt unless ($testapi::username eq 'root');
    if ($wait > 0) {
        return wait_serial("$str-\\d+-");
    }
    return;
}

# Simplified but still colored prompt for better readability.
sub set_standard_prompt {
    my ($self, $user, $os_type) = @_;
    $user ||= $testapi::username;
    $os_type ||= 'linux';
    my $prompt_sign = $user eq 'root' ? '#' : '$';
    if ($os_type eq 'windows') {
        $prompt_sign = $user eq 'root' ? '# ' : '$$ ';
        type_string "prompt $prompt_sign\n";
    }
    elsif ($os_type eq 'linux') {
        type_string "which tput 2>&1 && PS1=\"\\\[\$(tput bold 2; tput setaf 1)\\\]$prompt_sign\\\[\$(tput sgr0)\\\] \"\n";
    }
}

1;
# vim: sw=4 et ts=4:
