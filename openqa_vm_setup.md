# Running Tests in an openSUSE VM

This is an example of setting up an [openQA][openqa] server with this set of
tests and a worker inside an openSUSE QEMU VM.  The goal is to demonstrate
deploying of openQA test environment and its use for testing of QubesOS.

Full-fledged testing instance will require significantly more resources, likely
involve running workers on separate (physical) machines and possibly intricate
hardware setup.  Running an instance like this can suffice for simple tests that
involve installation of QubesOS, adding/updating dom0 packages and doing system
interactions during boot process or in dom0.  In particular this is useful
during development before moving to a more elaborate setup.

## Software Versions

* openSUSE: `Leap 15.5`
* openQA: `4.6.1667810206.2bf912d`

## Documentation

Instructions are available at <http://open.qa/docs/>.  The first part called
"openQA starter guide" gives a nice general overview of openQA.

## openSUSE Installation

Download network installer ISO (203 MiB) for openSUSE Leap 15.5 from
[here][opensuse-download] ([ISO][netinst-iso]):
```
wget -O opensuse.iso https://download.opensuse.org/distribution/leap/15.5/iso/openSUSE-Leap-15.5-NET-x86_64-Media.iso
```

Create a disk of suitable size (QCOW2 format grows on demand, it won't actually
reach 128 GiB unless you'll fill it up that much, but it will grow to around
20-60 GiB):
```
qemu-img create -f qcow2 disk.qcow2 128G
```

Start QEMU to perform the installation (use the same command to run the VM
later, possibly dropping `-cdrom opensuse.iso` part):
```
qemu-system-x86_64 -m 6G \
                   -cdrom opensuse.iso \
                   -machine q35,accel=kvm \
                   -drive if=virtio,file=disk.qcow2,format=qcow2 \
                   -cpu host \
                   -smp `nproc` \
                   -netdev user,id=mynet0,hostfwd=tcp:127.0.0.1:4151-:22,hostfwd=tcp:127.0.0.1:4150-:80 \
                   -device virtio-net,netdev=mynet0
```

### Installation Process

The installer is quite standard and easy to use, so won't go into much detail.

1. Pick "Installation" in boot menu, booting and then starting the installer
   will take some time as it downloads packages.
2. Accept license, probably keep English locale to keep it simple.
3. Agree to activate "Online Repositories", then press "Next" to actually do it
   (default state of the list seems sensible).  Wait for a bit.
4. Pick "Server" for system role as we don't need any desktop environment.
5. Accept default partitioning (BTRFS with a bunch of subvolumes) or adjust to
   something like: boot partition, EXT4 root and no swap.
6. Pick a time zone.  Can use localtime to avoid time difference in Web-UI.
7. Don't bother creating a regular user.
8. Pick root's password.
9. Installation summary:
   * Can disable CPU Mitigations in "Security" section for slightly better
     performance.
   * SSH should already be enabled in "Security" section.
10. Hit "Install" and come back in about 5 minutes.

### First Boot

Connect via SSH:
```
ssh -p 4151 root@127.0.0.1
```

Either disable AppArmor with `systemctl mask --now apparmor` or extend its
configuration by editing `/etc/apparmor.d/local/usr.share.openqa.script.worker`
to add:
```
/proc/cpuinfo r,
/usr/bin/base64 rix,
/usr/bin/tar rix,
/usr/bin/bash rix,
/var/lib/openqa/share/tests/qubesos/utils/* rk,
/var/lib/openqa/share/factory/hdd/* rk,
/var/lib/openqa/share/factory/hdd/fixed/* rk,
/var/lib/openqa/share/factory/iso/* rk,
/var/lib/openqa/share/factory/iso/fixed/* rk,
/var/lib/openqa/share/factory/repo/** r,
```

### openQA Setup

Install both server and worker (about 600 packages in total):
```
zypper install -y openQA openQA-worker
```

Setup Apache reverse proxy:
```
/usr/share/openqa/script/configure-web-proxy
systemctl enable apache2
systemctl restart apache2
```

Either disable `firewalld` through `systemctl disable firewalld` or allow access
to TCP port 80:
```
firewall-cmd --zone=public --add-port=80/tcp
firewall-cmd --zone=public --add-port=80/tcp --permanent
```

Configure authorization in `/etc/openqa/openqa.ini` (`Fake` should be fine as
long as the server is not publicly accessible):
```
[auth]
method = Fake
```

Start everything:
```
systemctl enable --now openqa-webui
systemctl enable --now openqa-scheduler
systemctl enable --now openqa-worker@1
```

At this point openQA should be accessible at <http://127.0.0.1:4150> and "Login"
link should activate "Demo" account.

Open the main menu (top-right corner) and select "Manage API keys"
(<http://127.0.0.1:4150/api_keys>).  Remove `1234567890ABCDEF` key as it will
expire soon and create a new one that doesn't expire.  Edit
`/etc/openqa/client.conf` to look like this:
```
[localhost]
key = INSERT_KEY_FROM_WEB_UI
secret = INSERT_SECRET_FROM_WEB_UI
```
The file is read-only, so save as `:w!` in Vim.

Now `openqa-cli` command should be able to send jobs, but don't do that yet
because they will be rejected.

### openQA Configuration

There are still things to do in Web-UI before anything can be tested.
If you see a specific name below, it will be referenced in some other place as
well, but can be customized otherwise just make sure to update all occurrences.

#### Manual Process

Go to "Medium types" (<http://127.0.0.1:4150/admin/products>) and add a new
installation ISO medium for QubesOS 4.2 (button is below the list):
 - Distri: `qubesos`
 - Version: `4.2`
 - Flavor: `install-iso`
 - Arch: `x86_64`

Don't forget to press "Save" icon.

Go to "Test suites" (<http://127.0.0.1:4150/admin/test_suites>) and add a new
one:
 - Name: `test-suite`

Go to "Machines" (<http://127.0.0.1:4150/admin/machines>) and add a new one:
 - Name: `qemu`
 - Backend: `qemu`
 - Settings:
   ```
   HDDSIZEGB=80
   PART_TABLE_TYPE=mbr
   QEMUCPU=host,+vmx
   QEMUCPUS=2
   QEMURAM=2048
   QEMU_APPEND=device VGA,edid=on,xres=1024,yres=768
   QEMU_DISABLE_SNAPSHOTS=1
   VIRTIO_CONSOLE=1
   ```

`QEMU_APPEND` makes needles match, otherwise the screen is somewhat distorted.

QubesOS/Xen needing 2 GiB of RAM is the reason for giving 6 GiB to openSUSE VM.
Can use less for openSUSE, but if jobs fail for seemingly no reason, check
`dmesg` for `OOM` messages and add more RAM (4 GiB without swap wasn't enough).
[Official requirements][qubesos-requirements] are 6 GiB at a minimum, so 2 GiB
is a bare minimum, extend as needed.

Go to "Job group" (<http://127.0.0.1:4150/admin/groups>) and create a new one
with a name of your choice.  Then click on the group to edit it and paste this
minimal configuration:
```yaml
defaults:
  x86_64:
    machine: qemu
    priority: 70
products:
  qubesos-4.2-install-iso-x86_64:
    distri: qubesos
    flavor: install-iso
    version: '4.2'
scenarios:
  x86_64:
    qubesos-4.2-install-iso-x86_64:
    - test-suite
```
Press "Save changes" button and don't mind weird "No changes were made!"
message.  If there is an error, make sure that previous steps were performed
correctly.

#### Automatic Process

After performing all steps manually, it's possible to export the configuration
with `openqa-dump-templates --json > templates.json`.  So an alternative to
clicking Web-UI, save the block below to a file (`templates.json`) and run
`openqa-load-templates templates.json` to recreate the same state:

```
{
   "Machines" : [
      {
         "backend" : "qemu",
         "settings" : [
            {
               "key" : "HDDSIZEGB",
               "value" : "80"
            },
            {
               "value" : "mbr",
               "key" : "PART_TABLE_TYPE"
            },
            {
               "key" : "QEMUCPU",
               "value" : "host,+vmx"
            },
            {
               "key" : "QEMUCPUS",
               "value" : "2"
            },
            {
               "key" : "QEMURAM",
               "value" : "2048"
            },
            {
               "value" : "device VGA,edid=on,xres=1024,yres=768",
               "key" : "QEMU_APPEND"
            },
            {
               "value" : "1",
               "key" : "QEMU_DISABLE_SNAPSHOTS"
            },
            {
               "key" : "VIRTIO_CONSOLE",
               "value" : "1"
            }
         ],
         "name" : "qemu"
      }
   ],
   "TestSuites" : [
      {
         "name" : "test-suite",
         "settings" : []
      }
   ],
   "Products" : [
      {
         "arch" : "x86_64",
         "settings" : [],
         "distri" : "qubesos",
         "version" : "4.2",
         "flavor" : "install-iso"
      }
   ],
   "JobTemplates" : [],
   "JobGroups" : [
      {
         "group_name" : "job-group",
         "template" : "defaults:\n  x86_64:\n    machine: qemu\n    priority: 70\nproducts:\n  qubesos-4.2-install-iso-x86_64:\n    distri: qubesos\n    flavor: install-iso\n    version: '4.2'\nscenarios:\n  x86_64:\n    qubesos-4.2-install-iso-x86_64:\n    - test-suite\n"
      }
   ]
}
```

This repository also includes `templates.json` file used to test QubesOS at
<https://openqa.qubes-os.org/> which can be imported to get a similar setup.

Mind that importing can fail if an object under the same name (e.g., job group)
already exists, so this works best for an initial setup or backup recovery.

### Adding QubesOS Test Suite

```
git clone --depth=1 https://github.com/QubesOS/openqa-tests-qubesos /var/lib/openqa/tests/qubesos
# to be able to edit needles in Web-UI
chown -R geekotest /var/lib/openqa/tests/qubesos
```

### Enqueueing a Job

Put some QubesOS installation ISO for a test, for example:
```
scp -P 4151 Qubes-20230621-x86_64.iso root@127.0.0.1:/var/lib/openqa/factory/iso/
```

And run (in the VM because `/etc/openqa/client.conf` was configured there and
this avoids installing anything outside of it):
```
openqa-cli api -X POST isos ISO=Qubes-20230621-x86_64.iso DISTRI=qubesos VERSION=4.2 FLAVOR=install-iso ARCH=x86_64 BUILD=20230621
```

Output like this with an empty `"failed"` array signifies a success:
```
{"count":1,"failed":[],"ids":[1],"scheduled_product_id":1}
```

Now go to <http://127.0.0.1:4150/>, select the job which should be already
running and see the start of the installation process by clicking on the little
blue circle in the second column.

[openqa]: http://open.qa/
[opensuse-download]: https://get.opensuse.org/leap/15.5/#download
[netinst-iso]: https://download.opensuse.org/distribution/leap/15.5/iso/openSUSE-Leap-15.5-NET-x86_64-Media.iso
[qubesos-requirements]: https://www.qubes-os.org/doc/system-requirements/
