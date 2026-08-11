import { useState, useEffect, useCallback, useRef } from "react"
// @ts-ignore
import SplitText from "./TextHome"

interface Slide {
  image: string
  eyebrow: string
  title: string
  subtitle: string
}

interface Props {
  slides: Slide[]
  interval?: number
}

export default function HeroCarousel({ slides, interval = 5000 }: Props) {
  const [current, setCurrent]         = useState(0)
  const [paused, setPaused]           = useState(false)
  const [textKey, setTextKey]         = useState(0)
  const [transitioning, setTransitioning] = useState(false)  
  const currentRef                    = useRef(0)

  const goTo = (index: number) => {
    setTransitioning(true)              
    setTimeout(() => {
      setCurrent(index)
      currentRef.current = index
      setTextKey(k => k + 1)            
      setTransitioning(false)            
    }, 120)                              
  }

  const next = useCallback(() => {
    goTo((currentRef.current + 1) % slides.length)
  }, [slides.length])

  const prev = () => {
    goTo((currentRef.current - 1 + slides.length) % slides.length)
  }

  useEffect(() => {
    if (paused) return
    const timer = setInterval(next, interval)
    return () => clearInterval(timer)
  }, [next, interval, paused])

  const slide = slides[current]

  return (
    <div
      className="carousel"
      style={{ "--dot-duration": `${interval}ms` } as React.CSSProperties}
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
    >
      {slides.map((s, i) => (
        <div
          key={s.image}
          className="carousel__slide"
          style={{
            backgroundImage: `url(${s.image})`,
            opacity: i === current ? 1 : 0,
          }}
          aria-hidden={i !== current}
        />
      ))}

      <div className="carousel__overlay" />

      <div className={`carousel__content ${transitioning ? "carousel__content--hidden" : ""}`}>

        <span className="carousel__eyebrow" key={`eyebrow-${textKey}`}>
          <SplitText
            text={slide.eyebrow}
            delay={25}
            duration={0.7}
            ease="power3.out"
            splitType="chars"
            from={{ opacity: 0, y: 15 }}
            to={{ opacity: 1, y: 0 }}
            threshold={0.1}
            textAlign="center"
          />
        </span>

        <h1 className="carousel__title" key={`title-${textKey}`}>
          <SplitText
            text={slide.title}
            delay={35}
            duration={1.1}
            ease="power3.out"
            splitType="chars"
            from={{ opacity: 0, y: 40 }}
            to={{ opacity: 1, y: 0 }}
            threshold={0.1}
            textAlign="center"
          />
        </h1>

        <span className="carousel__subtitle" key={`sub-${textKey}`}>
          <SplitText
            text={slide.subtitle}
            delay={60}
            duration={0.5}
            ease="power2.out"
            splitType="words"
            from={{ opacity: 0, y: 18 }}
            to={{ opacity: 1, y: 0 }}
            threshold={0.1}
            textAlign="center"
          />
        </span>

        {/* <div className="carousel__actions" key={`actions-${textKey}`}>
          <a href="/reservar" className="carousel__btn carousel__btn--primary">
            Reservar ahora
          </a>
          <a href="/habitaciones" className="carousel__btn carousel__btn--secondary">
            Ver habitaciones
          </a>
        </div> */}
      </div>

      <button className="carousel__arrow carousel__arrow--prev" onClick={prev} aria-label="Anterior">
        &#8249;
      </button>
      <button className="carousel__arrow carousel__arrow--next" onClick={next} aria-label="Siguiente">
        &#8250;
      </button>

      {/* Puntos */}
      <div className="carousel__dots">
        {slides.map((_, i) => (
          <button
            key={i}
            className={`carousel__dot ${i === current ? "carousel__dot--active" : ""}`}
            onClick={() => goTo(i)}
            aria-label={`Slide ${i + 1}`}
          />
        ))}
      </div>

      <style>{`
        .carousel {
          position: absolute;
          inset: 0;
          z-index: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: visible;          /* fix 3: no recortar nada */
        }

        /* ── Imágenes ── */
        .carousel__slide {
          position: absolute;
          inset: 0;
          background-size: cover;
          background-position: center;
          transition: opacity 1.4s ease;
        }

        .carousel__overlay {
          position: absolute;
          inset: 0;
          background: linear-gradient(
            135deg,
            rgba(27, 58, 107, 0.50) 0%,
            rgba(18, 40, 80, 0.58) 100%
          );
          z-index: 1;
        }

        /* ── Contenido ── */
        .carousel__content {
          position: relative;
          z-index: 2;
          max-width: 700px;
          text-align: center;
          padding: 0 1.5rem;
          transition: opacity 0.1s ease;   /* fix 1: fade out suave */
          overflow: visible;               /* fix 3 */
        }

        /* fix 1: clase que oculta durante la transición */
        .carousel__content--hidden {
          opacity: 0;
          pointer-events: none;
        }

        .carousel__eyebrow {
          display: block;
          color: #C9A84C;
          font-size: 0.9rem;
          font-weight: 600;
          letter-spacing: 0.15em;
          text-transform: uppercase;
          margin-bottom: 1rem;
          overflow: visible;
        }

        .carousel__title {
          color: #ffffff;
          font-size: clamp(2.5rem, 6vw, 4.5rem);
          font-weight: 700;
          font-family: Georgia, serif;
          line-height: 1.3;              /* fix 3: era 1.1, subido para descendentes */
          margin-bottom: 1.25rem;
          overflow: visible;             /* fix 3: nunca recortar letras */
          padding-bottom: 0.1em;        /* fix 3: espacio extra para g, p, y */
        }

        .carousel__subtitle {
          display: block;
          color: rgba(255, 255, 255, 0.85);
          font-size: 1.1rem;
          line-height: 1.7;
          margin-bottom: 2.5rem;
          overflow: visible;
        }

        /* ── Botones ── */
        .carousel__actions {
          display: flex;
          gap: 1rem;
          justify-content: center;
          flex-wrap: wrap;
          animation: fadeUp 0.6s ease 0.4s both;  /* aparece después del texto */
        }

        @keyframes fadeUp {
          from { opacity: 0; transform: translateY(16px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        .carousel__btn {
          text-decoration: none;
          font-size: 0.9375rem;
          font-weight: 600;
          padding: 0.75rem 1.75rem;
          border-radius: 6px;
          transition: transform 0.2s, background 0.2s;
        }

        .carousel__btn:hover { transform: translateY(-2px); }

        .carousel__btn--primary {
          background: #C9A84C;
          color: #1B3A6B;
        }

        .carousel__btn--primary:hover { background: #B8962F; }

        .carousel__btn--secondary {
          background: transparent;
          color: #ffffff;
          border: 1.5px solid rgba(255,255,255,0.5);
        }

        .carousel__btn--secondary:hover { border-color: #ffffff; }

        /* ── Flechas ── */
        .carousel__arrow {
          position: absolute;
          top: 50%;                           /* fix: quitado el // que lo comentaba */
          transform: translateY(-50%);
          z-index: 3;
          background: rgba(253, 253, 253, 0);
          border: 1px solid rgba(255, 255, 255, 0);
          color: white;
          font-size: 3rem;
          width: 50px;
          height: 50px;
          border-radius: 50%;
          cursor: pointer;
          display: flex;
          align-items: center;
          justify-content: center;
          transition: background 0.2s, opacity 0.2s;
          padding-bottom: 3px;
        }

        .carousel__arrow:hover { background: rgba(255, 255, 255, 0); }
        .carousel__arrow--prev { left: 1.5rem; }
        .carousel__arrow--next { right: 1.5rem; }

        /* ── Puntos ── */
        .carousel__dots {
          position: absolute;
          bottom: 1.75rem;
          left: 50%;
          transform: translateX(-50%);
          z-index: 3;
          display: flex;
          gap: 6px;
          align-items: center;
        }

        .carousel__dot {
          width: 28px;
          height: 3px;
          border-radius: 2px;
          border: none;
          background: rgba(255, 255, 255, 0.35);
          cursor: pointer;
          padding: 0;
          transition: background 0.3s, width 0.3s;
          position: relative;
          overflow: hidden;
        }

        .carousel__dot--active {
          width: 52px;
          background: rgba(255, 255, 255, 0.25);
        }
        
        .carousel__dot--active::after {
          content: "";
          position: absolute;
          inset: 0;
          background: #C9A84C;
          transform-origin: left;
          animation: dotProgress var(--dot-duration, 5000ms) linear forwards;
        }

        @keyframes dotProgress {
          from { transform: scaleX(0); }
          to   { transform: scaleX(1); }
        }

        /* ── Móvil ── */
        @media (max-width: 768px) {
          /* flechas desaparecen en móvil */
          .carousel__arrow {
            display: none;
          }

          /* puntos más pequeños en móvil */
          .carousel__dots {
            bottom: 1.25rem;
            gap: 5px;
          }

          .carousel__dot {
            width: 20px;
            height: 3px;
          }

          .carousel__dot--active {
            width: 36px;
          }

          .carousel__content {
            padding: 0 1rem;
            padding-bottom: 4rem;
          }

          .carousel__title {
            font-size: clamp(2rem, 10vw, 2.75rem);
          }

          .carousel__subtitle {
            font-size: 0.95rem;
            margin-bottom: 2rem;
          }

          .carousel__actions {
            flex-direction: column;
            align-items: stretch;
          }

          .carousel__btn {
            text-align: center;
            padding: 0.875rem 1.25rem;
            font-size: 1rem;
          }
        }

        @media (max-width: 380px) {
          .carousel__title { font-size: 1.75rem; }
        }
      `}</style>
    </div>
  )
}