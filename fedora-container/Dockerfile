FROM fedora:43

# Install OpenSSH server
RUN dnf install -y openssh-server passwd && \
    dnf clean all

# Generate SSH host keys
RUN ssh-keygen -A

# Set root password and enable root login
RUN echo 'root:scan123' | chpasswd && \
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Expose SSH port
EXPOSE 22

# Start SSH daemon
CMD ["/usr/sbin/sshd", "-D"]
