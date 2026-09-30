"""conduit URL Configuration

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/1.10/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  url(r'^$', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  url(r'^$', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.conf.urls import url, include
    2. Add a URL to urlpatterns:  url(r'^blog/', include('blog.urls'))
"""
from django.urls import include, re_path
from django.contrib import admin
from conduit.apps.core.views import healthcheck

urlpatterns = [
    re_path(r'^admin/', admin.site.urls),
    re_path(r'^healthz/?$', healthcheck, name='healthcheck'),

    re_path(r'^api/', include('conduit.apps.articles.urls', namespace='articles')),
    re_path(r'^api/', include('conduit.apps.authentication.urls', namespace='authentication')),
    re_path(r'^api/', include('conduit.apps.profiles.urls', namespace='profiles')),
]
