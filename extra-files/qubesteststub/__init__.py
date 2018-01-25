
import qubes.ext
import qubes.vm.qubesvm

class DefaultPV(qubes.ext.Extension):
    def __init__(self):
        super().__init__()
        qubes.vm.qubesvm.QubesVM.virt_mode._default = 'pv'
        qubes.vm.qubesvm.QubesVM.virt_mode._default_function = None
