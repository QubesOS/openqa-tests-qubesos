import asyncio
import subprocess
import pathlib
import os

import qubes.ext
import qubes.vm.qubesvm
import xen.lowlevel.xc
from qubes.devices import DeviceAssignment

class DefaultPV(qubes.ext.Extension):

    @qubes.ext.handler('domain-pre-start')
    async def on_domain_pre_start(self, vm, event, **kwargs):
        # on Xen 4.13 PCI passthrough on PV requires IOMMU too
        pv_passthrough_available = (self.xeninfo['xen_minor'] < 13 or 
            'qubes.enable_insecure_pv_passthrough' in self.dom0_cmdline)
        if 'hvm_directio' not in self.physinfo['virt_caps'] and not pv_passthrough_available:
            # FIXME: new devices API
            if vm.name in ('sys-net', 'sys-usb'):
                for ass in list(vm.devices['pci'].assignments()):
                    await vm.devices['pci'].detach(ass)
        elif 'hvm_directio' in self.physinfo['virt_caps'] or pv_passthrough_available:
            # IOMMU is available, (re)attach devices
            if vm.name == 'sys-net':
                missing = set(self.netdevs)
            elif vm.name == 'sys-usb':
                missing = set(self.usbdevs)
            else:
                missing = set()

            if hasattr(vm.devices['pci'], 'get_assigned_devices'):
                # new devices API
                for dev in vm.devices['pci'].get_assigned_devices():
                    if hasattr(dev, "port"):
                        missing.discard(dev.port.port_id.replace('_', ':'))
                    else:
                        missing.discard(dev.ident.replace('_', ':'))
                for dev in missing:
                    if hasattr(DeviceAssignment, "new"):
                        ass = DeviceAssignment.new(vm.app.domains[0], dev.replace(':', '_'), "pci",
                                options={'no-strict-reset': 'True'},
                                mode="required")
                    else:
                        ass = DeviceAssignment(vm.app.domains[0], dev.replace(':', '_'),
                                options={'no-strict-reset': 'True'},
                                required=True, attach_automatically=True)
                    await vm.devices['pci'].assign(ass)
            else:
                # old devices API
                for dev in vm.devices['pci'].persistent():
                    missing.discard(dev.ident.replace('_', ':'))
                for dev in missing:
                    ass = DeviceAssignment(vm.app.domains[0], dev.replace(':', '_'),
                            options={'no-strict-reset': 'True'},
                            persistent=True)
                    await vm.devices['pci'].attach(ass)

        has_pci_devices = (len(list(vm.devices['pci'].get_assigned_devices()))
                           if hasattr(vm.devices['pci'], 'get_assigned_devices')
                           else len(vm.devices['pci'].persistent()))
        if has_pci_devices:
            # IOMMU missing
            if 'hvm_directio' not in self.physinfo['virt_caps'] and vm.virt_mode != 'pv':
                vm.virt_mode = 'pv'
            elif 'hvm_directio' in self.physinfo['virt_caps'] and vm.virt_mode != 'hvm':
                vm.virt_mode = 'hvm'
            if os.path.exists('/sys/firmware/efi') and vm.virt_mode == 'pv':
                # on UEFI (OVMF) disable e820_host, otherwise guest crashes;
                # but then, force swiotlb as without e820_host automatic detection
                # doesn't work in Linux (since f9a38ea5172a3365f4594335ed5d63e15af2fd18)
                vm.features['pci-e820-host'] = False
                vm.kernelopts += " iommu=soft"

    @qubes.ext.handler('domain-start')
    async def on_domain_start(self, vm, event, **kwargs):
        has_pci_devices = (len(list(vm.devices['pci'].get_assigned_devices()))
                           if hasattr(vm.devices['pci'], 'get_assigned_devices')
                           else len(vm.devices['pci'].persistent()))
        if vm.name == 'sys-net' and not has_pci_devices:
            for dev in self.netdevs:
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/pciback/unbind'.format(dev), shell=True)
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/e1000e/bind'.format(dev), shell=True)
            # wait for udev and co
            await asyncio.sleep(1)
            subprocess.call('udevadm settle', shell=True)
            await asyncio.sleep(1)
            iface = subprocess.check_output('ls /sys/class/net|grep ^en', shell=True).decode()
            iface = iface.strip()
            subprocess.call('ip link add name xenbr0 type bridge', shell=True)
            subprocess.call('ip link set dev {} master xenbr0'.format(iface), shell=True)
            subprocess.call('ip l s {} up'.format(iface), shell=True)
            subprocess.call('ip l s xenbr0 up', shell=True)
            subprocess.call('xl network-attach sys-net bridge=xenbr0', shell=True)
        if vm.name == 'sys-usb' and not has_pci_devices:
            for dev in self.usbdevs:
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/pciback/unbind'.format(dev), shell=True)
                subprocess.call('echo 0000:{} > /sys/bus/pci/drivers/ehci-pci/bind'.format(dev), shell=True)

    def __init__(self):
        super().__init__()
        x = xen.lowlevel.xc.xc()
        self.physinfo = x.physinfo()
        self.xeninfo = x.xeninfo()
        del x
        if 'hvm' not in self.physinfo['virt_caps']:
            qubes.vm.qubesvm.QubesVM.virt_mode._default = 'pv'
            qubes.vm.qubesvm.QubesVM.virt_mode._default_function = None
            qubes.vm.qubesvm.QubesVM.virt_mode._setter = lambda _self, _prop, _value: 'pv'

        self.netdevs = []
        self.usbdevs = []
        lspci = subprocess.check_output(['lspci', '-n']).decode()
        for line in lspci.splitlines():
            bdf = line.split()[0]
            if '0200:' in line:
                self.netdevs.append(bdf)
            if '0c03:' in line:
                self.usbdevs.append(bdf)

        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default = 120
        qubes.vm.qubesvm.QubesVM.qrexec_timeout._default_function = None
        if 'xen_scrub_pages' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' xen_scrub_pages=0'
            qubes.config.defaults['kernelopts_pcidevs'] += ' xen_scrub_pages=0'
        if 'journald' not in qubes.config.defaults['kernelopts']:
            qubes.config.defaults['kernelopts'] += ' systemd.journald.forward_to_console=1 systemd.journald.max_level_console=debug'
            qubes.config.defaults['kernelopts_pcidevs'] += ' systemd.journald.forward_to_console=1 systemd.journald.max_level_console=debug'

        self.dom0_cmdline = pathlib.Path('/proc/cmdline').read_bytes().decode()

    @qubes.ext.handler('features-request')
    async def on_features_request(self, vm, event, untrusted_features):
        if vm.klass != 'TemplateVM':
            return
        if not vm.features.get('fixups-installed', False):
            # nested virtualization confuses systemd
            dropin = '/etc/systemd/system/xendriverdomain.service.d'
            await vm.run_for_stdio('mkdir -p {dropin} && echo -e "[Unit]\\nConditionVirtualization=" > {dropin}/30_openqa.conf'.format(dropin=dropin), user='root')
            vm.features['fixups-installed'] = True

    @qubes.ext.handler('domain-start-failed')
    def on_start_failed(self, vm, event, **kwargs):
        import time
        print('VM {} start failed at {}'.format(vm.name, time.strftime('%F %T')))
