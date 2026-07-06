from django.urls import path

from . import views

urlpatterns = [
    path("images/", views.images, name="images"),
    path("images/<str:image_id>/", views.image_detail, name="image-detail"),
]
