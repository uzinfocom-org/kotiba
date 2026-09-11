try:
    from test_driver.machine import QemuMachine
    machine: QemuMachine = machine
except:
    pass

machine.start()
machine.wait_for_unit("multi-user.target")
machine.succeed("uname -a")

machine.wait_for_unit("kotiba")
machine.succeed("systemctl status kotiba")
machine.succeed("echo kotiba is up")
machine.wait_for_open_port(4343)
machine.succeed("curl --fail http://localhost:4343/health")


