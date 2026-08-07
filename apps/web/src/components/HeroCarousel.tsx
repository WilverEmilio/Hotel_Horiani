import { useState, useEffect, useCallback } from "react"

interface Props {
  images: string[]
  interval?: number  // ms entre imágenes, default 5000
}

export default function HeroCarousel({ images, interval = 5000 }: Props) {
  const [current, setCurrent] = useState(0)
  const [paused, setPaused]   = useState(false)

  const next = useCallback(() => {
    setCurrent(c => (c + 1) % images.length)
  }, [images.length])

  const prev = () => {
    setCurrent(c => (c - 1 + images.length) % images.length)
  }

  // Auto-avance
  useEffect(() => {
    if (paused) return
    const timer = setInterval(next, interval)
    return () => clearInterval(timer)
  }, [next, interval, paused])

  return (
    <div
      className="carousel"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      aria-label="Carrusel de imágenes del hotel"
    >
      {/* Imágenes apiladas con crossfade */}
      {images.map((src, i) => (
        <div
          key={src}
          className="carousel__slide"
          style={{
            backgroundImage: `url(${src})`,
            opacity: i === current ? 1 : 0,
          }}
          aria-hidden={i !== current}
        />
      ))}

      {/* Overlay oscuro para legibilidad del texto */}
      <div className="carousel__overlay" />

      {/* Flechas */}
      <button className="carousel__arrow carousel__arrow--prev" onClick={prev} aria-label="Imagen anterior">
        &#8249;
      </button>
      <button className="carousel__arrow carousel__arrow--next" onClick={next} aria-label="Siguiente imagen">
        &#8250;
      </button>

      {/* Puntos de navegación */}
      <div className="carousel__dots" role="tablist">
        {images.map((_, i) => (
          <button
            key={i}
            className={`carousel__dot ${i === current ? "carousel__dot--active" : ""}`}
            onClick={() => setCurrent(i)}
            aria-label={`Ir a imagen ${i + 1}`}
            aria-selected={i === current}
            role="tab"
          />
        ))}
      </div>

      <style>{`
        .carousel {
          position: absolute;
          inset: 0;
          z-index: 0;
        }

        .carousel__slide {
          position: absolute;
          inset: 0;
          background-size: cover;
          background-position: center;
          transition: opacity 1.2s ease;
        }

        .carousel__overlay {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            135deg,
            rgba(98, 118, 150, 0.15) 0%,
            rgba(18, 40, 80, 0.65) 100%
          );
          z-index: 1;
        }

        .carousel__arrow {
          position: absolute;
          top: 50%;
          transform: translateY(-50%);
          z-index: 2;
          background: rgba(255,255,255,0.12);
          border: 1px solid rgba(255,255,255,0.25);
          color: white;
          font-size: 2.5rem;
          line-height: 1;
          width: 48px;
          height: 48px;
          border-radius: 50%;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: background 0.2s;
          padding-bottom: 3px;
        }

        .carousel__arrow:hover {
          background: rgba(255,255,255,0.22);
        }

        .carousel__arrow--prev { left: 1.5rem; }
        .carousel__arrow--next { right: 1.5rem; }

        .carousel__dots {
          position: absolute;
          bottom: 1.75rem;
          left: 50%;
          transform: translateX(-50%);
          z-index: 2;
          display: flex;
          gap: 8px;
        }

        .carousel__dot {
          width: 8px;
          height: 8px;
          border-radius: 50%;
          border: none;
          background: rgba(255,255,255,0.4);
          cursor: pointer;
          transition: background 0.3s, transform 0.3s;
          padding: 0;
        }

        .carousel__dot--active {
          background: #C9A84C;
          transform: scale(1.35);
        }
        @media (max-width: 768px) {
          .carousel__arrow {
            width: 40px;
            height: 40px;
            font-size: 2rem;
          }

          .carousel__arrow--prev { left: 0.75rem; }
          .carousel__arrow--next { right: 0.75rem; }

          .carousel__dots {
            bottom: 1.25rem;
            gap: 10px;         /* puntos más separados para el dedo */
          }

          .carousel__dot {
            width: 10px;       /* puntos más grandes para tocar fácil */
            height: 10px;
          }
        }
      `}</style>
    </div>
  )
}