import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { deleteImage, fetchImages, type ImageItem } from '../api'
import CopyButton from '../components/CopyButton'

export default function GalleryPage() {
  const [images, setImages] = useState<ImageItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [filter, setFilter] = useState('') // '' = all folders
  const [deletingId, setDeletingId] = useState<ImageItem['id'] | null>(null)

  useEffect(() => {
    let active = true
    fetchImages()
      .then((imgs) => {
        if (active) {
          setImages(imgs)
          setLoading(false)
        }
      })
      .catch((err) => {
        if (active) {
          setError(err instanceof Error ? err.message : 'Could not load images')
          setLoading(false)
        }
      })
    return () => {
      active = false
    }
  }, [])

  const folders = useMemo(
    () => [...new Set(images.map((i) => i.folder_name).filter(Boolean))].sort(),
    [images],
  )

  const visible = useMemo(
    () => (filter ? images.filter((i) => i.folder_name === filter) : images),
    [images, filter],
  )

  async function onDelete(img: ImageItem) {
    if (!window.confirm(`Delete "${img.title}"? This cannot be undone.`)) return

    setDeletingId(img.id)
    const previous = images
    setImages((imgs) => imgs.filter((i) => i.id !== img.id)) // optimistic

    try {
      await deleteImage(img.id)
    } catch (err) {
      setImages(previous) // roll back on failure
      window.alert(err instanceof Error ? err.message : 'Failed to delete image')
    } finally {
      setDeletingId(null)
    }
  }

  if (loading) return <p className="status">Loading images…</p>
  if (error) return <p className="status error">{error}</p>

  if (images.length === 0) {
    return (
      <div className="empty-state">
        <p>No images yet.</p>
        <Link to="/" className="btn primary">Add your first image</Link>
      </div>
    )
  }

  return (
    <section>
      <div className="gallery-head">
        <h1>Gallery</h1>
        <div className="gallery-controls">
          {folders.length > 0 && (
            <select
              className="folder-select"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
            >
              <option value="">All folders ({images.length})</option>
              {folders.map((f) => (
                <option key={f} value={f}>
                  {f} ({images.filter((i) => i.folder_name === f).length})
                </option>
              ))}
            </select>
          )}
          <Link to="/" className="btn">+ Add image</Link>
        </div>
      </div>

      <div className="grid">
        {visible.map((img) => (
          <figure key={img.id} className="tile">
            <img src={img.image_url} alt={img.title} loading="lazy" />
            <figcaption>
              <div className="tile-title">{img.title}</div>
              {img.folder_name && <span className="badge">{img.folder_name}</span>}
              <div className="tile-actions">
                <CopyButton url={img.image_url} className="btn copy-btn" />
                <button
                  type="button"
                  className="btn copy-btn danger"
                  onClick={() => onDelete(img)}
                  disabled={deletingId === img.id}
                >
                  {deletingId === img.id ? 'Deleting…' : 'Delete'}
                </button>
              </div>
            </figcaption>
          </figure>
        ))}
      </div>
    </section>
  )
}
