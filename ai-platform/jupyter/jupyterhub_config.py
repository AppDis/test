c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'

# Admin del hub (crear primero desde la UI de registro)
c.Authenticator.admin_users = {'admin'}

# Los estudiantes no pueden registrarse solos — el admin los crea
c.NativeAuthenticator.open_signup = False

# Accesible desde nginx en /jupyter/
c.JupyterHub.base_url = '/jupyter/'
c.JupyterHub.ip = '0.0.0.0'
c.JupyterHub.port = 8000

# JupyterLab como interfaz por defecto (no el Notebook clásico)
c.Spawner.default_url = '/lab'

# Directorio de trabajo de cada estudiante
c.Spawner.notebook_dir = '/home/{username}'
