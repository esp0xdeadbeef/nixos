# Runs under KVM on s-nodus, so the guest must match the board. This is the only
# place its architecture is stated; every other VM defaults to x86_64-linux.
{ system = "aarch64-linux"; }
