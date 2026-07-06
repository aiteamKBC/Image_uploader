import { NavLink, Route, Routes } from 'react-router-dom'
import UploadPage from './pages/UploadPage'
import GalleryPage from './pages/GalleryPage'

function navClass({ isActive }: { isActive: boolean }) {
  return isActive ? 'nav-link active' : 'nav-link'
}

export default function App() {
  return (
    <div className="app">
      <header className="nav">
        <span className="brand">🖼️ Image Uploader</span>
        <nav className="nav-links">
          <NavLink to="/" end className={navClass}>Upload</NavLink>
          <NavLink to="/gallery" className={navClass}>Gallery</NavLink>
        </nav>
      </header>

      <main className="container">
        <Routes>
          <Route path="/" element={<UploadPage />} />
          <Route path="/gallery" element={<GalleryPage />} />
        </Routes>
      </main>
    </div>
  )
}
