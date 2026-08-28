import { useState } from "react"
import "./HBCarts.css"
import {GaleriaModal, Modal} from "./detalleHB";

const CORNER_PATH = "M0 200C155.996 199.961 200.029 156.308 200 0V200H0Z"

interface Habitacion {
  image: string[]
  badge: string
  label: string
  titulo: string
  desc: string
}

const habitaciones: Habitacion[] = [
  {
    image: ["/images/Gallery/pasillo1.jpeg", "/images/Gallery/pasillo4.jpeg", "/images/Gallery/pasillo2.jpeg"],
    badge: "Popular",
    label: "Individual",
    titulo: "Habitación Individual",
    desc: "Perfecta para viajeros solos. Cama individual, baño privado y WiFi gratuito incluido.",
  },
  {
    image: ["/images/Gallery/pasillo2.jpeg","/images/Gallery/pasillo4.jpeg","/images/Gallery/pasillo1.jpeg"],
    badge: "Popular",
    label: "Doble",
    titulo: "Habitación Doble",
    desc: "Ideal para parejas o compañeros de viaje. Dos camas, baño privado y vista a la ciudad.",

  },
  {
    image: ["/images/Gallery/pasillo4.jpeg","/images/Gallery/pasillo1.jpeg","/images/Gallery/pasillo2.jpeg"],
    badge: "Popular",
    label: "Suite",
    titulo: "Suite Ejecutiva",
    desc: "Nuestra habitación más espaciosa. Sala de estar, escritorio y vista panorámica a Quetzaltenango.",
  },
  
]

function Corner({ className }: { className?: string }) {
  return (
    <svg
      aria-hidden
      className={className}
      width={28}
      height={28}
      viewBox="0 0 200 200"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path d={CORNER_PATH} fill="currentColor" />
    </svg>
  )
}

function HabitacionCard({ h }: { h: Habitacion }) {
  const [hovered, setHovered] = useState(false)
  const [isModalOpen, setIsModalOpen] = useState(false);

  return (
    <div
      className={`hcard${hovered ? " hcard--hovered" : ""}`}
      onMouseEnter={() => setHovered(true)}
      onMouseLeave={() => setHovered(false)}
    >
      <div className="hcard__media">
        <img
          src={h.image[0]}
          alt={h.titulo}
          className="hcard__img"
          draggable={false}
        />
        <div className="hcard__overlay" />

        <div className="hcard__pin">{h.badge}</div>

        <div className="hcard__label">
          <span>{h.label}</span>
          <Corner className="hcard__corner hcard__corner--right" />
          <Corner className="hcard__corner hcard__corner--top" />
        </div>
      </div>

      <div className="hcard__content">
        <h3 className="hcard__titulo">{h.titulo}</h3>
        <p className="hcard__desc">{h.desc}</p>

        <div className="hcard__footer">
          <button
            type="button"
            onClick={() => {setIsModalOpen(true) 
              setHovered(false)} }
            className={`hcard__btn${hovered ? " hcard__btn--visible" : ""}`}
          >
            Detalle →
          </button>
        </div>
      </div>

      <Modal
      isOpen={isModalOpen}
      onClose={()=> {setIsModalOpen(false)
        setHovered(false)
      }}
      title={h.titulo}
      >
        <GaleriaModal images={h.image}/>
        <p className="p_modal">
          {h.desc}
        </p>
      </Modal>
    </div>
  )
}

export default function HabitacionesCards() {
  return (
    <div className="hcards">
      {habitaciones.map(h => (
        <HabitacionCard key={h.titulo} h={h} />
      ))}
    </div>
  )
}