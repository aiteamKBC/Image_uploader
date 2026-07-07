import {
  useEffect,
  useRef,
  useState,
  type ChangeEvent,
  type DragEvent,
  type FormEvent,
} from 'react'
import { Link } from 'react-router-dom'
import { fetchImages, uploadImage, type ImageItem } from '../api'
import CopyButton from '../components/CopyButton'

type Phase = 'idle' | 'uploading' | 'processing' | 'done' | 'error'
type SelectedImage = { file: File; preview: string; key: string; title: string }

const NEW_FOLDER = '__new__'
const MAX_UPLOAD_BYTES = 200 * 1024 * 1024 // keep in sync with backend MAX_UPLOAD_SIZE

function titleFromFilename(filename: string) {
  return filename.replace(/\.[^.]+$/, '').replace(/[-_]+/g, ' ').trim() || 'Untitled image'
}

export default function UploadPage() {
  const [folder, setFolder] = useState('')
  const [addingFolder, setAddingFolder] = useState(false)
  const [newFolderName, setNewFolderName] = useState('')
  const [selected, setSelected] = useState<SelectedImage[]>([])
  const [dragging, setDragging] = useState(false)

  const [phase, setPhase] = useState<Phase>('idle')
  const [progress, setProgress] = useState(0)
  const [currentUpload, setCurrentUpload] = useState(0)
  const [error, setError] = useState('')
  const [results, setResults] = useState<ImageItem[]>([])
  const [folders, setFolders] = useState<string[]>([])

  const fileInputRef = useRef<HTMLInputElement>(null)
  const selectedRef = useRef<SelectedImage[]>([])

  useEffect(() => {
    fetchImages()
      .then((imgs) => {
        const names = [...new Set(imgs.map((i) => i.folder_name).filter(Boolean))]
        setFolders(names.sort())
      })
      .catch(() => {
        /* Folder suggestions are optional. */
      })
  }, [])

  useEffect(() => {
    selectedRef.current = selected
  }, [selected])

  useEffect(() => {
    return () => selectedRef.current.forEach((item) => URL.revokeObjectURL(item.preview))
  }, [])

  function addFiles(files: File[]) {
    const notImage = files.some((file) => !file.type.startsWith('image/'))
    const images = files.filter((file) => file.type.startsWith('image/') && file.size <= MAX_UPLOAD_BYTES)
    const tooLarge = files.some((file) => file.type.startsWith('image/') && file.size > MAX_UPLOAD_BYTES)

    if (tooLarge) {
      setError(`Some images are larger than ${MAX_UPLOAD_BYTES / (1024 * 1024)} MB and were ignored.`)
    } else if (notImage) {
      setError('Only image files can be added. Other files were ignored.')
    } else {
      setError('')
    }

    setSelected((current) => {
      const existing = new Set(current.map((item) => item.key))
      const additions = images
        .map((file) => ({
          file,
          preview: URL.createObjectURL(file),
          key: `${file.name}-${file.size}-${file.lastModified}`,
          title: titleFromFilename(file.name),
        }))
        .filter((item) => {
          if (existing.has(item.key)) {
            URL.revokeObjectURL(item.preview)
            return false
          }
          existing.add(item.key)
          return true
        })
      return [...current, ...additions]
    })
  }

  function onFileChange(e: ChangeEvent<HTMLInputElement>) {
    addFiles(Array.from(e.target.files ?? []))
    e.target.value = ''
  }

  function onDrop(e: DragEvent<HTMLButtonElement>) {
    e.preventDefault()
    setDragging(false)
    if (!busy) addFiles(Array.from(e.dataTransfer.files))
  }

  function removeFile(key: string) {
    setSelected((current) => {
      const removed = current.find((item) => item.key === key)
      if (removed) URL.revokeObjectURL(removed.preview)
      return current.filter((item) => item.key !== key)
    })
  }

  function updateFileTitle(key: string, title: string) {
    setSelected((current) => current.map((item) => (
      item.key === key ? { ...item, title } : item
    )))
  }

  function onFolderSelect(e: ChangeEvent<HTMLSelectElement>) {
    const value = e.target.value
    if (value === NEW_FOLDER) {
      setAddingFolder(true)
      setNewFolderName('')
      setFolder('')
    } else {
      setAddingFolder(false)
      setFolder(value)
    }
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (!canSubmit) return

    const folderToUse = (addingFolder ? newFolderName : folder).trim()
    const queue = [...selected]
    const uploaded: ImageItem[] = []
    const failed: SelectedImage[] = []
    const failures: string[] = []

    setPhase('uploading')
    setProgress(0)
    setCurrentUpload(1)
    setError('')
    setResults([])

    for (let index = 0; index < queue.length; index += 1) {
      const item = queue[index]
      setCurrentUpload(index + 1)
      setPhase('uploading')
      try {
        const image = await uploadImage(
          item.title.trim(),
          item.file,
          folderToUse,
          (percent) => {
            setProgress(Math.round(((index + percent / 100) / queue.length) * 100))
            if (percent >= 100) setPhase('processing')
          },
        )
        uploaded.push(image)
        URL.revokeObjectURL(item.preview)
      } catch (err) {
        failed.push(item)
        failures.push(`${item.file.name}: ${err instanceof Error ? err.message : 'Upload failed'}`)
      }
    }

    setResults(uploaded)
    setSelected(failed)
    setProgress(100)
    if (uploaded.length > 0) {
      setPhase('done')
      if (folderToUse && !folders.includes(folderToUse)) {
        setFolders((prev) => [...prev, folderToUse].sort())
      }
      setFolder(folderToUse)
      setAddingFolder(false)
      setNewFolderName('')
    } else {
      setPhase('error')
    }

    if (failures.length) {
      setError(`${uploaded.length} uploaded, ${failed.length} failed. ${failures.join(' ')}`)
    }
  }

  const busy = phase === 'uploading' || phase === 'processing'
  const folderValid = !addingFolder || newFolderName.trim().length > 0
  const titleValid = selected.every((item) => item.title.trim().length > 0)
  const canSubmit = selected.length > 0 && titleValid && folderValid && !busy

  return (
    <section className="card form-card">
      <h1>Upload images</h1>
      <p className="subtitle">Choose one image or upload a whole batch.</p>

      <form onSubmit={onSubmit} className="form">
        <div className="field">
          <span className="label">Folder <span className="optional">(optional)</span></span>
          <select
            className="folder-select full-width"
            value={addingFolder ? NEW_FOLDER : folder}
            onChange={onFolderSelect}
            disabled={busy}
          >
            <option value="">No folder</option>
            {folders.map((f) => <option key={f} value={f}>{f}</option>)}
            <option value={NEW_FOLDER}>+ Add new folder…</option>
          </select>

          {addingFolder && (
            <input
              type="text"
              value={newFolderName}
              onChange={(e) => setNewFolderName(e.target.value)}
              placeholder="New folder name"
              maxLength={100}
              disabled={busy}
              autoFocus
            />
          )}
        </div>

        <div className="field">
          <span className="label">Images</span>
          <button
            type="button"
            className={`dropzone ${dragging ? 'dragging' : ''}`}
            onClick={() => fileInputRef.current?.click()}
            onDragEnter={(e) => { e.preventDefault(); if (!busy) setDragging(true) }}
            onDragOver={(e) => e.preventDefault()}
            onDragLeave={(e) => {
              e.preventDefault()
              if (!e.currentTarget.contains(e.relatedTarget as Node | null)) setDragging(false)
            }}
            onDrop={onDrop}
            disabled={busy}
          >
            <span className="dropzone-empty">
              <span className="dropzone-icon">⇧</span>
              <span><strong>Drag and drop images here</strong></span>
              <span>or click to browse</span>
              <span className="hint">Select multiple PNG, JPG, GIF, or WebP files (up to 200 MB each)</span>
            </span>
          </button>
          <input
            ref={fileInputRef}
            type="file"
            accept="image/*"
            multiple
            onChange={onFileChange}
            hidden
          />

          {selected.length > 0 && (
            <div className="upload-list" aria-label="Selected images">
              <p className="selection-count">{selected.length} image{selected.length === 1 ? '' : 's'} selected</p>
              {selected.map((item) => (
                <div className="upload-item" key={item.key}>
                  <img src={item.preview} alt="" />
                  <div className="upload-item-details">
                    <input
                      type="text"
                      value={item.title}
                      onChange={(e) => updateFileTitle(item.key, e.target.value)}
                      placeholder="Image title"
                      maxLength={200}
                      disabled={busy}
                      aria-label={`Title for ${item.file.name}`}
                    />
                    <span title={item.file.name}>{item.file.name}</span>
                  </div>
                  <button
                    type="button"
                    className="remove-file"
                    onClick={() => removeFile(item.key)}
                    disabled={busy}
                    aria-label={`Remove ${item.file.name}`}
                  >×</button>
                </div>
              ))}
            </div>
          )}
        </div>

        {busy && (
          <div className="field">
            <div className="progress-track">
              <div className="progress-bar" style={{ width: `${progress}%` }} />
            </div>
            <p className="progress-label">
              {phase === 'processing' ? 'Saving' : 'Uploading'} image {currentUpload} of {selected.length}… {progress}%
            </p>
          </div>
        )}

        {error && <p className="error">{error}</p>}

        <button type="submit" className="btn primary" disabled={!canSubmit}>
          {busy ? 'Uploading…' : selected.length > 1 ? `Upload ${selected.length} images` : 'Upload image'}
        </button>
      </form>

      {results.length > 0 && (
        <div className="success-panel">
          <p className="success-title">✓ {results.length} image{results.length === 1 ? '' : 's'} uploaded successfully</p>
          {results.length === 1 && (
            <>
              <img src={results[0].image_url} alt={results[0].title} className="success-thumb" />
              <div className="url-row">
                <input type="text" readOnly value={results[0].image_url} onFocus={(e) => e.target.select()} />
                <CopyButton url={results[0].image_url} className="btn primary" />
              </div>
            </>
          )}
          {results.length > 1 && (
            <div className="bulk-results">
              {results.map((image) => (
                <div className="bulk-result-item" key={image.id ?? image.image_url}>
                  <img src={image.image_url} alt="" />
                  <span title={image.title}>{image.title}</span>
                  <CopyButton url={image.image_url} className="btn primary copy-btn" />
                </div>
              ))}
            </div>
          )}
          <Link to="/gallery" className="view-gallery-link">View in gallery →</Link>
        </div>
      )}
    </section>
  )
}
