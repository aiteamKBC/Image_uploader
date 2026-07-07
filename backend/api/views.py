"""Image API backed by Supabase.

Mounted at ``/api/images/``:

* ``GET``  -> list every saved image (title + public URL) from the table.
* ``POST`` -> accept a multipart form (``title`` + ``image`` file), upload the
              file to a Supabase Storage bucket, then insert a metadata row.

Mounted at ``/api/images/<id>/``:

* ``DELETE`` -> remove the file from Storage and its row from the table.
"""

import mimetypes
import uuid

from django.conf import settings
from django.http import HttpResponse, JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_http_methods

from .supabase_client import get_supabase


@csrf_exempt
@require_http_methods(["GET", "POST"])
def images(request):
    """Route GET -> list, POST -> create."""
    if request.method == "GET":
        return _list_images()
    return _create_image(request)


def _list_images():
    supabase = get_supabase()
    try:
        result = (
            supabase.table(settings.SUPABASE_TABLE)
            .select("*")
            .order("created_at", desc=True)
            .execute()
        )
    except Exception as exc:  # network / policy / missing-table errors
        return JsonResponse({"error": f"Could not load images: {exc}"}, status=502)

    return JsonResponse({"images": result.data})


def _create_image(request):
    title = (request.POST.get("title") or "").strip()
    folder_name = (request.POST.get("folder_name") or "").strip()
    upload = request.FILES.get("image")

    if not title:
        return JsonResponse({"error": "A title is required."}, status=400)
    if upload is None:
        return JsonResponse({"error": "An image file is required."}, status=400)
    if upload.size > settings.MAX_UPLOAD_SIZE:
        limit_mb = settings.MAX_UPLOAD_SIZE // (1024 * 1024)
        return JsonResponse(
            {"error": f"Image is too large. The limit is {limit_mb} MB."}, status=413
        )

    # Build a collision-proof storage path, keeping the original extension.
    extension = upload.name.rsplit(".", 1)[-1].lower() if "." in upload.name else "bin"
    path = f"{uuid.uuid4().hex}.{extension}"
    content_type = (
        upload.content_type
        or mimetypes.guess_type(upload.name)[0]
        or "application/octet-stream"
    )

    supabase = get_supabase()
    bucket = supabase.storage.from_(settings.SUPABASE_BUCKET)

    # 1) Upload the raw file bytes to the Storage bucket.
    try:
        bucket.upload(
            path,
            upload.read(),
            {"content-type": content_type, "upsert": "true"},
        )
    except Exception as exc:
        return JsonResponse({"error": f"Storage upload failed: {exc}"}, status=502)

    # 2) Build the public URL for the freshly uploaded file.
    public_url = bucket.get_public_url(path)

    # 3) Save the metadata row in the "image" table.
    record = {
        "title": title,
        "image_url": public_url,
        "path": path,
        "folder_name": folder_name,
    }
    try:
        result = (
            supabase.table(settings.SUPABASE_TABLE)
            .insert(record)
            .execute()
        )
    except Exception as exc:
        return JsonResponse({"error": f"Saving the record failed: {exc}"}, status=502)

    row = result.data[0] if result.data else record
    return JsonResponse({"image": row}, status=201)


@csrf_exempt
@require_http_methods(["DELETE"])
def image_detail(request, image_id):
    supabase = get_supabase()

    # Look up the row first so we know which Storage file to remove.
    try:
        result = (
            supabase.table(settings.SUPABASE_TABLE)
            .select("path")
            .eq("id", image_id)
            .execute()
        )
    except Exception as exc:
        return JsonResponse({"error": f"Could not look up image: {exc}"}, status=502)

    if not result.data:
        return JsonResponse({"error": "Image not found."}, status=404)

    path = result.data[0].get("path")
    bucket = supabase.storage.from_(settings.SUPABASE_BUCKET)

    if path:
        try:
            bucket.remove([path])
        except Exception as exc:
            return JsonResponse({"error": f"Storage delete failed: {exc}"}, status=502)

    # `.select()` on a delete makes Postgres return the deleted row(s), so we
    # can tell a *real* delete apart from a no-op silently swallowed by RLS
    # (a delete blocked by policy returns success with an empty list, not an
    # error).
    try:
        delete_result = (
            supabase.table(settings.SUPABASE_TABLE)
            .delete()
            .eq("id", image_id)
            .execute()
        )
    except Exception as exc:
        return JsonResponse({"error": f"Deleting the record failed: {exc}"}, status=502)

    if not delete_result.data:
        return JsonResponse(
            {
                "error": (
                    "The image row was not deleted. This is usually a missing "
                    "DELETE row-level-security policy on the 'image' table in "
                    "Supabase — re-run supabase_setup.sql."
                )
            },
            status=502,
        )

    return HttpResponse(status=204)
