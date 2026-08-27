import React, { type ReactNode} from 'react';
import './detalleHB.css'

interface ModalProps {
    isOpen: boolean;
    onClose: () => void;
    title: string
    children: ReactNode;
}

export const Modal: React.FC<ModalProps> = ({isOpen, onClose, title, children}) => {
 if (!isOpen) return null;
 
 return(
    <div className="modal-overlay" onClick={onClose}>
        <div className='modal-container' onClick={(e) => e.stopPropagation}>
            <div className='modal-header'>
                <h3>{title}</h3>
                <button className='modal-close-btn' onClick={onClose}>&times;</button>
            </div>
            <div className='modal-body'>
                {children}
            </div>
        </div>
    </div>
 )
}
