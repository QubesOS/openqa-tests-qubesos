
import qubes.ext
import qubes.vm.qubesvm
import xen.lowlevel.xc

class DefaultPV(qubes.ext.Extension):

    @qubes.ext.handler('domain-pre-start')
    def on_domain_pre_start(self, vm, event, **kwargs):
        if len(vm.devices['pci'].persistent()):
            # IOMMU missing
            if 'hvm_directio' not in self.physinfo['virt_caps'] and vm.virt_mode != 'pv':
                vm.virt_mode = 'pv'
            # disable e820_host, otherwise guest crashes when host booted with OVMF
            vm.features['pci-e820-host'] = False

    def __init__(self):
        super().__init__()
        x = xen.lowlevel.xc.xc()
        self.physinfo = x.physinfo()
        del x
        if 'hvm' not in self.physinfo['virt_caps']:
            qubes.vm.qubesvm.QubesVM.virt_mode._default = 'pv'
            qubes.vm.qubesvm.QubesVM.virt_mode._default_function = None
            qubes.vm.qubesvm.QubesVM.virt_mode._setter = lambda _self, _prop, _value: 'pv'
