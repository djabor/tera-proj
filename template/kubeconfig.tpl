apiVersion: v1
clusters:
  - cluster:
      server: ${server}
      certificate-authority-data: ${certificate_authority_data}
    name: ${name}
contexts:
  - context:
      cluster: ${name}
      user: ${name}
    name: ${name}
current-context: ${name}
kind: Config
preferences: {}
users:
  - name: ${name}
    user:
      token: ${token}