// Small client for the Django image API.
// The base URL is configurable via frontend/.env (VITE_API_URL) and
// falls back to the default local Django dev server.
const API_URL = import.meta.env.VITE_API_URL ?? 'http://localhost:8000'

export interface ImageItem {
  id: number | string
  title: string
  image_url: string
  path: string
  folder_name: string
  created_at?: string
}

/** Fetch every saved image (newest first). */
export async function fetchImages(): Promise<ImageItem[]> {
  const res = await fetch(`${API_URL}/api/images/`)
  const data = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error(data.error ?? 'Failed to load images')
  }
  return data.images ?? []
}

/**
 * Upload one image (title + folder + file) to the backend.
 *
 * Uses XMLHttpRequest (not fetch) so we can report real upload progress via
 * `onProgress`. The percentage tracks the browser -> Django transfer; once it
 * reaches 100% the backend is still forwarding the file to Supabase, so the UI
 * should show a "processing" state until this promise resolves.
 */
export function uploadImage(
  title: string,
  file: File,
  folderName: string,
  onProgress?: (percent: number) => void,
): Promise<ImageItem> {
  return new Promise((resolve, reject) => {
    const form = new FormData()
    form.append('title', title)
    form.append('image', file)
    form.append('folder_name', folderName)

    const xhr = new XMLHttpRequest()
    xhr.open('POST', `${API_URL}/api/images/`)

    xhr.upload.onprogress = (e) => {
      if (e.lengthComputable && onProgress) {
        onProgress(Math.round((e.loaded / e.total) * 100))
      }
    }

    xhr.onload = () => {
      let data: { image?: ImageItem; error?: string } = {}
      try {
        data = JSON.parse(xhr.responseText)
      } catch {
        // Non-JSON response (e.g. a server crash page); handled below.
      }
      if (xhr.status >= 200 && xhr.status < 300 && data.image) {
        resolve(data.image)
      } else {
        reject(new Error(data.error ?? `Upload failed (status ${xhr.status})`))
      }
    }

    xhr.onerror = () => reject(new Error('Network error during upload'))
    xhr.send(form)
  })
}

/** Delete a saved image (removes both the Storage file and its table row). */
export async function deleteImage(id: ImageItem['id']): Promise<void> {
  const res = await fetch(`${API_URL}/api/images/${id}/`, { method: 'DELETE' })
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error(data.error ?? 'Failed to delete image')
  }
}
