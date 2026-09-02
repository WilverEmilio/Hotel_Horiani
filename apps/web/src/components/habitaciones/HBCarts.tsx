import { useState } from "react"
import "./HBCarts.css"
import {GaleriaModal, Modal} from "./detalleHB";
import habitaciones from "../../data/habitaciones.json"

interface Habitacion {
  titulo: string
  desc: string
  image: string[]
  label: string
  badge: string
  servicios?: string[]
}

const CORNER_PATH = "M0 200C155.996 199.961 200.029 156.308 200 0V200H0Z"


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

        {h.servicios && h.servicios.length > 0 && (
          <div className="servicios_modal">
            <h3 className="servicios_modal__title">
              Servicios incluidos
            </h3>

            <ul className="servicios_modal__list">
              {h.servicios.map((servicio, index) => (
                <li
                  key={index}
                  className="servicios_modal__item"
                >
                  <span className="servicios_modal__icon">
                    ✓
                  </span>

                  <span className="servicios_modal__text">
                    {servicio}
                  </span>
                </li>
              ))}
            </ul>
          </div>
        )}

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