# The Qubes OS Project, https://www.qubes-os.org/
#
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

use strict;
use testapi;
use autotest;
use OpenQA::Test::RunArgs;

require 'qubesdistribution.pm';
testapi::set_distribution(qubesdistribution->new());

if (get_var('ISO')) {
    autotest::loadtest "tests/isosize.pm";
    if (get_var('INSTALL_ISO_FILE')) {
        autotest::loadtest "tests/install_iso_file.pm";
    } elsif (get_var('INSTALL_OEM')) {
        autotest::loadtest "tests/install_oem.pm";
    } else {
        autotest::loadtest "tests/install_startup.pm";
    }
    if (get_var('INSTALL_OVER_EXISTING')) {
        autotest::loadtest "tests/install_preexisting_system.pm";
        autotest::loadtest "tests/install_startup_2.pm";
    }
    if (!get_var('INSTALL_OEM')) {
        autotest::loadtest "tests/install_welcome.pm";
        if (get_var('KEYBOARD_LAYOUT')) {
            autotest::loadtest "tests/install_keyboard.pm";
        }
        if (get_var('PARTITIONING')) {
            autotest::loadtest "tests/install_partitioning_" . get_var('PARTITIONING') . ".pm";
        } else {
            autotest::loadtest "tests/install_partitioning_default.pm";
        }
        if (check_var("VERSION", "4.0")) {
            autotest::loadtest "tests/install_templates.pm";
        }
    }
    autotest::loadtest "tests/install_do_user.pm";
    autotest::loadtest "tests/install_fixups.pm";
    autotest::loadtest "tests/firstboot.pm";
    if (get_var("INSTALL_TEMPLATES") =~ /\d+/) {
        # if a specific template version was requested, add it now
        autotest::loadtest "tests/update_templates.pm";
    }
    if (check_var('INSTALL_TEMPLATES', 'all') or get_var("INSTALL_TEMPLATES") =~ /whonix/) {
        autotest::loadtest "tests/whonix_firstrun.pm";
    }
    # 4.1+ can set default template in firstboot
    if (get_var("DEFAULT_TEMPLATE") and check_var("VERSION", "4.0")) {
        autotest::loadtest "tests/switch_template.pm";
    }
} elsif (get_var('TEST_AEM')) {
    autotest::loadtest "tests/aem.pm";
} else {
    autotest::loadtest "tests/startup.pm";
    if (get_var('DO_UPDATE')) {
        if (get_var('UPDATE_TEMPLATES')) {
            autotest::loadtest "tests/update_templates.pm";
        }
        if (get_var('UPDATE') || get_var('SALT_SYSTEM_TESTS')) {
            if (check_var("VERSION", "4.1")) {
                autotest::loadtest "tests/update.pm";
            } else {
                autotest::loadtest "tests/update2.pm";
            }
        }
        if (get_var('DISTUPGRADE_TEMPLATES')) {
            autotest::loadtest "tests/distupgrade_template.pm";
        }
        if (get_var("SELINUX_TEMPLATES")) {
            autotest::loadtest "tests/selinux_install.pm";
        }
        if (get_var('GUIVM') || get_var('GUIVM_VNC') || get_var('GUIVM_GPU')) {
            autotest::loadtest "tests/update_guivm.pm";
        }
    } else {
        autotest::loadtest "tests/fetch_packages_list.pm";
    }
    if (get_var("DEFAULT_TEMPLATE")) {
        autotest::loadtest "tests/switch_template.pm";
    }
    if (get_var('PARTITIONING')) {
        autotest::loadtest "tests/switch_pool.pm";
    }
}

if (check_var('RELEASE_UPGRADE', '1')) {
    if (get_var('UPDATE') || get_var('SALT_SYSTEM_TESTS')) {
        if (check_var("VERSION", "4.1")) {
            autotest::loadtest "tests/update.pm";
        } else {
            autotest::loadtest "tests/update2.pm";
        }
    }
    autotest::loadtest "tests/release_upgrade.pm";
}

if (get_var('DO_GUIVM')) {
    if (get_var('UPDATE_TEMPLATES')) {
        autotest::loadtest "tests/update_templates.pm";
        autotest::loadtest "tests/update_post_templates.pm";
    }
    if (get_var('GUIVM') || get_var('GUIVM_VNC') || get_var('GUIVM_GPU')) {
        autotest::loadtest "tests/update_guivm.pm";
    }
}

if (get_var('PIPEWIRE')) {
    autotest::loadtest "tests/pipewire_install.pm";
}

if (check_var('DESKTOP', 'kde')) {
    autotest::loadtest "tests/kde_install.pm";
    autotest::loadtest "tests/kde_startup.pm";
}

# do not execute same tests before each system tests run
if (check_var('TEST_GENERIC', '1') and
        (!get_var('DO_UPDATE') or check_var('RESTART_AFTER_UPDATE', '1'))) {
    autotest::loadtest "tests/mount_and_boot_options.pm";
    autotest::loadtest "tests/microcode.pm" if (check_var("BACKEND", "generalhw"));
    autotest::loadtest "tests/usbvm.pm";
}

if (check_var('TEST_GUIVM', '1')) {
    autotest::loadtest "tests/guivm_startup.pm";
    autotest::loadtest "tests/guivm_manager.pm";
}

if (check_var('TEST_FIDO', '1')) {
    autotest::loadtest "tests/fido.pm";
}

if (check_var('SUSPEND_MODE', 'S0ix')) {
    autotest::loadtest "tests/enable_s0ix.pm";
}
if (check_var('TEST_SUSPEND', '1')) {
    autotest::loadtest "tests/suspend.pm";
}

if (get_var("WHONIXCHECK")) {
    autotest::loadtest "tests/whonixcheck.pm";
}

if (get_var("WHONIX_INTERACTIVE")) {
    autotest::loadtest "tests/whonix_torbrowser.pm";
}

if (get_var('SYSTEM_TESTS')) {
    if (get_var('TEST_TEMPLATES', '') =~ /minimal/) {
        autotest::loadtest "tests/system_tests_prepare_minimal.pm";
    }
    if (check_var('SYSTEM_TESTS', 'qubesmanager.tests')) {
        autotest::loadtest "tests/system_tests_prepare_manager.pm";
    }
    autotest::loadtest "tests/system_tests.pm";
}

if (check_var('SECUREDROP_INSTALL', '1')) {

    # Setup sys-whonix connection so it does not interfere later
    autotest::loadtest("tests/whonix_firstrun.pm", name => "Setup_sys-whonix");

    autotest::loadtest("tests/securedrop/install_workstation.pm");

    # Setup sd-whonix connection
    my $args = OpenQA::Test::RunArgs->new();
    $args->{whonix_gw_override} = 'sd-whonix';
    autotest::loadtest("tests/whonix_firstrun.pm", name =>"Setup_sd-whonix",  run_args => $args);
    autotest::loadtest("tests/securedrop/install_workstation_updates.pm");
} elsif (check_var('SECUREDROP_TEST', "test_dom0")) {
    autotest::loadtest("tests/securedrop/test_dom0.pm");
} elsif (check_var('SECUREDROP_TEST', "test_gui")) {
    # SKIPPED awaiting completion
    # autotest::loadtest("tests/securedrop/server_setup.pm");
    # autotest::loadtest("tests/securedrop/server_start.pm");
    # autotest::loadtest("tests/securedrop/test_gui_basic.pm");
}

if (get_var('DISPVM_PRELOAD')) {
    autotest::loadtest "tests/dispvm_preload.pm";
}

if (get_var('TEST_GUI_INTERACTIVE')) {
    autotest::loadtest "tests/simple_gui_apps.pm";
    autotest::loadtest "tests/clipboard_and_web.pm";
    autotest::loadtest "tests/gui_filecopy.pm";
    autotest::loadtest "tests/screenlocker_idle_watch.pm";
    autotest::loadtest "tests/screenlocker_leaks.pm";
    autotest::loadtest "tests/screenlocker_disable.pm";
    autotest::loadtest "tests/gui_keyboard_layout.pm";
}

if (get_var("WINDOWS_VERSION")) {
    autotest::loadtest "tests/windows_install.pm";
}

if (get_var("TEST_WINDOWS_GUI_INTERACTIVE")) {
    autotest::loadtest "tests/windows_clipboard_and_filecopy.pm";
    autotest::loadtest "tests/suspend_windows.pm";
}

if (get_var("GUI_TESTS")) {
        autotest::loadtest "tests/desktop_linux_manager_create_qube.pm";
        autotest::loadtest "tests/desktop_linux_manager_config.pm";
        autotest::loadtest "tests/desktop_linux_manager_policy_edit.pm";

        autotest::loadtest "tests/qui_widgets_clipboard.pm";
        autotest::loadtest "tests/qui_widgets_devices.pm";
        autotest::loadtest "tests/qui_widgets_disk_space.pm";
        autotest::loadtest "tests/qui_widgets_domains.pm";
        autotest::loadtest "tests/qui_widgets_notifications.pm";
        autotest::loadtest "tests/qui_widgets_update.pm";

        if (check_var("VERSION", "4.2")) {
            autotest::loadtest "tests/qubesmanager_createnewvm.pm";
        }
        if (check_var("VERSION", "4.1")) {
            autotest::loadtest "tests/qubesmanager_globalsettings.pm";
        }
        autotest::loadtest "tests/qubesmanager_manager.pm";
        autotest::loadtest "tests/qubesmanager_templatemanager.pm";
        autotest::loadtest "tests/qubesmanager_vmsettings.pm";
        autotest::loadtest "tests/qubesmanager_backuprestore.pm";

}

if (get_var('TEST_GUI_INTERACTIVE')) {
    # collect logs from some successful test that is scheduled on all hw*
    # workers
    autotest::loadtest "tests/collect_logs.pm";
}

autotest::loadtest "tests/shutdown.pm";


1;

# vim: set sw=4 et:
